package inc::Beer::Admin;
$CUSTOM_VERSION = '0.01';
use strict;
my $PACKAGE = __PACKAGE__;
my $FILE = "$PACKAGE.pm"; $FILE =~ s!::!/!g;
if (-M "./inc/Beer/Admin.pm" != -M __FILE__ or -s "./inc/Beer/Admin.pm" != -s __FILE__) {
    # anti shoot-self-in-foot device
    delete $INC{"inc/Beer/Admin.pm"}; require "./inc/Beer/Admin.pm";
    purge_self();
}
else {
use vars qw(@EXPORT @EXPORT_OK %ARGS @MANIFEST @CLEAN @ISA);
@EXPORT = qw(WriteMakefile include);
@EXPORT_OK = qw(script prereq bundle inline can_run get_file check_nmake);

@ISA = 'Exporter';
require Exporter;
require ExtUtils::MakeMaker;
require File::Spec;
require Cwd;

# These should always be exported:
*main::WriteMakefile = \&WriteMakefile;
*main::prompt = \&ExtUtils::MakeMaker::prompt;
*main::include = \&include;

die "Please upgrade File::Spec. Version is too old to continue.\n"
  if $File::Spec::VERSION < 0.8;
die "$PACKAGE should only be used inside Makefile.PL\n"
  unless $0 =~ /Makefile\.PL$/i and -f 'Makefile.PL' or $0 eq '-e';

}

sub purge_self {
    my $file = __FILE__;
    unlink $file or return;
    my @parts = split('/', $FILE);

    foreach my $i (reverse(0 .. $#parts - 1)) {
	my $path = join('/', @parts[0..$i]);
	$path = substr($file, 0, rindex($file, $path) + length($path));
	rmdir $path or last;
    }
}

sub WriteMakefile {
    my %args = @_;
    %ARGS = ();

    $ARGS{NAME} = $args{NAME} if defined $args{NAME};
    $ARGS{VERSION} = $args{VERSION} if defined $args{VERSION};
    $ARGS{VERSION_FROM} = $args{VERSION_FROM} if defined $args{VERSION_FROM};
    $ARGS{NAME} = $main::NAME if defined $main::NAME;
    $ARGS{VERSION} = $main::VERSION if defined $main::VERSION;
    $ARGS{VERSION_FROM} = $main::VERSION_FROM if defined $main::VERSION_FROM;
    determine_NAME() unless defined $ARGS{NAME};
    determine_VERSION()
      unless defined $ARGS{VERSION} or defined $ARGS{VERSION_FROM};
    determine_CLEAN_FILES() 
      if defined $main::CLEAN_FILES or
         defined @main::CLEAN_FILES;
    $ARGS{ABSTRACT} = $main::ABSTRACT 
      if defined $main::ABSTRACT and $] >= 5.005;
    $ARGS{AUTHOR} = $main::AUTHOR 
      if defined $main::AUTHOR and $] >= 5.005;
    $ARGS{PREREQ_PM} = \%main::PREREQ_PM if defined %main::PREREQ_PM;
    $ARGS{PL_FILES} = \%main::PL_FILES if defined %main::PL_FILES;
    $ARGS{EXE_FILES} = \@main::EXE_FILES if defined @main::EXE_FILES;

    my %Args = (%ARGS, %args);
    ExtUtils::MakeMaker::WriteMakefile(%Args);
    fix_up_makefile();
}

sub determine_VERSION {
    my $VERSION = '';
    my @modules = (glob('*.pm'), grep {/\.pm$/} find_files('lib'));
    if (@modules == 1) {
        eval {
            $VERSION = ExtUtils::MM_Unix->parse_version($modules[0]);
        };
        print STDERR $@ if $@;
    }
    die <<END unless length($VERSION);
Can't determine a VERSION for this distribution.
Please pass a VERSION parameter to the WriteMakefile function in Makefile.PL.
END
#'
    $ARGS{VERSION} = $VERSION;
}

sub determine_NAME {
    my $NAME = '';
    my @modules = (glob('*.pm'), grep {/\.pm$/} find_files('lib'));
    if (@modules == 1) {
        open MODULE, $modules[0] or die $!;
        while (<MODULE>) {
            next if /^\s*#/;
	    print "looing at $_";
            if (/^\s*package\s+(\w[\w:]*)\s*;\s*$/) {
                $NAME = $1;
            }
            last;
        }
    }
    die <<END unless length($NAME);
Can't determine a NAME for this distribution.
Please pass a NAME parameter to the WriteMakefile function in Makefile.PL.
END
    return $NAME;
}

sub find_files {
    my ($file, $path) = @_;
    $path = '' if not defined $path;
    $file = "$path/$file" if length($path);
    if (-f $file) {
        return ($file);
    }
    elsif (-d $file) {
        my @files = ();
        local *DIR;
        opendir(DIR, $file) or die "Can't opendir $file";
        while (my $new_file = readdir(DIR)) {
            next if $new_file =~ /^(\.|\.\.)$/;
            push @files, find_files($new_file, $file);
        }
        return @files;
    }
    return ();
}

sub determine_CLEAN_FILES {
    my $clean_files = '';
    if (defined($main::CLEAN_FILES)) {
        if (ref($main::CLEAN_FILES) eq 'ARRAY') {
            $clean_files = join ' ', @$main::CLEAN_FILES;
        }
        else {
            $clean_files = $main::CLEAN_FILES;
        }
    }
    if (defined(@main::CLEAN_FILES)) {
        $clean_files = join ' ', ($clean_files, @main::CLEAN_FILES);
    }
    $clean_files = join ' ', ($clean_files, @CLEAN);
    $ARGS{clean} = {FILES => $clean_files};
}

sub fix_up_makefile {
    open MAKEFILE, '>> Makefile'
      or die "${PACKAGE}::WriteMakefile can't append to Makefile:\n$!";

    print MAKEFILE <<MAKEFILE;
# Well, not quite. $PACKAGE is adding this:

realclean purge ::
	\$(RM_F) \$(DISTVNAME).tar\$(SUFFIX)

reset :: purge
	\$(PERL) -I. -M$PACKAGE -e${PACKAGE}::purge_self

upload :: test dist
	cpan-upload -verbose \$(DISTVNAME).tar\$(SUFFIX)

grok ::
	perldoc $PACKAGE

distsign::
	cpansign -s

# The End is here ==>
MAKEFILE

    close MAKEFILE;
}

# check if we can run some command
sub can_run {
    my $command = shift;

    # absoluate pathname?
    return $command if (-x $command or $command = MM->maybe_command($command));

    require Config;
    for my $dir (split /$Config::Config{path_sep}/, $ENV{PATH}) {
        my $abs = File::Spec->catfile($dir, $command);
        return $abs if (-x $abs or $abs = MM->maybe_command($abs));
    }

    return;
}

# determine if the user needs nmake, and download it if needed
sub check_nmake {
    require Config;
    return unless (
        $Config::Config{make} =~ /^nmake\b/i and
        $^O eq 'MSWin32'             and
        !can_run('nmake')
    );

    print "The required 'nmake' executable not found, fetching it...\n";

    use File::Basename;
    my $rv = get_file(
	url	    => 'ftp://ftp.microsoft.com/Softlib/MSLFILES/nmake15.exe',
	local_dir   => dirname($^X),
	size	    => 51928,
	run	    => 'nmake15.exe /o > nul',
	check_for   => 'nmake.exe',
	remove	    => 1,
    );

    if (!$rv) {
	die << '.';

========================================================================

Since you are using Microsoft Windows, you will need the 'nmake' utility
before installation. It's available at:

    ftp://ftp.microsoft.com/Softlib/MSLFILES/nmake15.exe

Please download the file manually, save it to a directory in %PATH (e.g.
C:\WINDOWS\COMMAND), then launch the MS-DOS command line shell, "cd" to
that directory, and run "nmake15.exe" from there; that will create the
'nmake.exe' file needed by this module.

You may then resume the installation process described in README.

========================================================================
.
    }
}

# fetch nmake from Microsoft's FTP site
sub get_file {
    my %args = @_;

    my ($scheme, $host, $path, $file) = 
	$args{url} =~ m|^(\w+)://([^/]+)(.+)/(.+)| or return;

    return unless $scheme eq 'ftp';

    unless (eval { require Socket; Socket::inet_aton($host) }) {
        print "Cannot fetch 'nmake'; '$host' resolve failed!\n";
        return;
    }

    use Cwd;
    my $dir = getcwd;
    chdir $args{local_dir} or return if exists $args{local_dir};

    $|++;
    print "Fetching '$file' from $host. It may take a few minutes... ";

    if (eval { require Net::FTP; 1 }) {
        # use Net::FTP to get pass firewall
        my $ftp = Net::FTP->new($host, Passive => 1, Timeout => 600);
        $ftp->login("anonymous", 'anonymous@example.com');
        $ftp->cwd($path);
        $ftp->binary;
        $ftp->get($file) or die $!;
        $ftp->quit;
    }
    elsif (can_run('ftp')) {
        # no Net::FTP, fallback to ftp.exe
        require FileHandle;
        my $fh = FileHandle->new;

        local $SIG{CHLD} = 'IGNORE';
        unless ($fh->open("|ftp.exe -n")) {
            warn "Couldn't open ftp: $!";
            chdir $dir; return;
        }

        my @dialog = split(/\n/, << ".");
open $host
user anonymous anonymous\@example.com
cd $path
binary
get $file $file
quit
.
        foreach (@dialog) { $fh->print("$_\n") }
        $fh->close;
    }
    else {
        print "Cannot fetch '$file' without a working 'ftp' executable!\n";
        chdir $dir; return;
    }

    return if exists $args{size} and -s $file != $args{size};
    system($args{run}) if exists $args{run};
    unlink($file) if $args{remove};

    print (((!exists $args{check_for} or -e $args{check_for})
	? "done!" : "failed! ($!)"), "\n");
    chdir $dir; return !$?;
}

1;

