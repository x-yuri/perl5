#!./perl -w
package ExtUtils::Miniperl;
use strict;
use Exporter 'import';
use ExtUtils::Embed 1.31, qw(xsi_header xsi_protos xsi_body);

our @EXPORT = qw(writemain);
our $VERSION = '1.12';

# blead will run this with miniperl, hence we can't use autodie or File::Temp
my $temp;

END {
    return if !defined $temp || !-e $temp;
    unlink $temp or warn "Can't unlink '$temp': $!";
}

sub writemain{
    my ($fh, $real);

    if (ref $_[0] eq 'SCALAR') {
        $real = ${+shift};
        $temp = $real;
        $temp =~ s/(?:.c)?\z/.new/;
        open $fh, '>', $temp
            or die "Can't open '$temp' for writing: $!";
    } elsif (ref $_[0]) {
        $fh = shift;
    } else {
        $fh = \*STDOUT;
    }

    my(@exts) = @_;

    printf $fh <<'EOF!HEAD', xsi_header();
/*    miniperlmain.c or perlmain.c - a generated file
 *
 *    Copyright (C) 1994, 1995, 1996, 1997, 1999, 2000, 2001, 2002, 2003,
 *    2004, 2005, 2006, 2007, 2016 by Larry Wall and others
 *
 *    You may distribute under the terms of either the GNU General Public
 *    License or the Artistic License, as specified in the README file.
 *
 */

/*
 *      The Road goes ever on and on
 *          Down from the door where it began.
 *
 *     [Bilbo on p.35 of _The Lord of the Rings_, I/i: "A Long-Expected Party"]
 *     [Frodo on p.73 of _The Lord of the Rings_, I/iii: "Three Is Company"]
 */

/* This file contains the main() function for the perl interpreter.
 * Note that miniperlmain.c contains main() for the 'miniperl' binary,
 * while perlmain.c contains main() for the 'perl' binary. The typical
 * difference being that the latter includes Dynaloader.
 *
 * Miniperl is like perl except that it does not support dynamic loading,
 * and in fact is used to build the dynamic modules needed for the 'real'
 * perl executable.
 *
 * The content of the body of this generated file is mostly contained
 * in Miniperl.pm - edit that file if you want to change anything.
 * miniperlmain.c is generated by running regen/miniperlmain.pl, while
 * perlmain.c is built automatically by Makefile (so the former is
 * included in the tarball while the latter isn't).
 */

#ifdef OEMVS
#ifdef MYMALLOC
/* sbrk is limited to first heap segment so make it big */
#pragma runopts(HEAP(8M,500K,ANYWHERE,KEEP,8K,4K) STACK(,,ANY,) ALL31(ON))
#else
#pragma runopts(HEAP(2M,500K,ANYWHERE,KEEP,8K,4K) STACK(,,ANY,) ALL31(ON))
#endif
#endif

#define PERL_IN_MINIPERLMAIN_C

/* work round bug in MakeMaker which doesn't currently (2019) supply this
 * flag when making a statically linked perl */
#define PERL_CORE 1

%s
static void xs_init (pTHX);
static PerlInterpreter *my_perl;

#ifdef NO_ENV_ARRAY_IN_MAIN
extern char **environ;
int
main(int argc, char **argv)
#else
int
main(int argc, char **argv, char **env)
#endif
{
    int exitstatus, i;
#ifndef NO_ENV_ARRAY_IN_MAIN
    PERL_UNUSED_ARG(env);
#endif

    /* if user wants control of gprof profiling off by default */
    /* noop unless Configure is given -Accflags=-DPERL_GPROF_CONTROL */
    PERL_GPROF_MONCONTROL(0);

#ifdef NO_ENV_ARRAY_IN_MAIN
    PERL_SYS_INIT3(&argc,&argv,&environ);
#else
    PERL_SYS_INIT3(&argc,&argv,&env);
#endif

#if defined(USE_ITHREADS)
    /* XXX Ideally, this should really be happening in perl_alloc() or
     * perl_construct() to keep libperl.a transparently fork()-safe.
     * It is currently done here only because Apache/mod_perl have
     * problems due to lack of a call to cancel pthread_atfork()
     * handlers when shared objects that contain the handlers may
     * be dlclose()d.  This forces applications that embed perl to
     * call PTHREAD_ATFORK() explicitly, but if and only if it hasn't
     * been called at least once before in the current process.
     * --GSAR 2001-07-20 */
    PTHREAD_ATFORK(Perl_atfork_lock,
                   Perl_atfork_unlock,
                   Perl_atfork_unlock);
#endif

    PERL_SYS_FPU_INIT;

    if (!PL_do_undump) {
	my_perl = perl_alloc();
	if (!my_perl)
	    exit(1);
	perl_construct(my_perl);
	PL_perl_destruct_level = 0;
    }
    PL_exit_flags |= PERL_EXIT_DESTRUCT_END;
    if (!perl_parse(my_perl, xs_init, argc, argv, (char **)NULL))
        perl_run(my_perl);

#ifndef PERL_MICRO
    /* Unregister our signal handler before destroying my_perl */
    for (i = 1; PL_sig_name[i]; i++) {
	if (rsignal_state(PL_sig_num[i]) == (Sighandler_t) PL_csighandlerp) {
	    rsignal(PL_sig_num[i], (Sighandler_t) SIG_DFL);
	}
    }
#endif

    exitstatus = perl_destruct(my_perl);

    perl_free(my_perl);

    PERL_SYS_TERM();

    exit(exitstatus);
}

/* Register any extra external extensions */

EOF!HEAD

    print $fh xsi_protos(@exts), <<'EOT', xsi_body(@exts), "}\n";

static void
xs_init(pTHX)
{
EOT

    if ($real) {
        close $fh or die "Can't close '$temp': $!";
        rename $temp, $real or die "Can't rename '$temp' to '$real': $!";
    }
}

1;
__END__

=head1 NAME

ExtUtils::Miniperl - write the C code for miniperlmain.c and perlmain.c

=head1 SYNOPSIS

    use ExtUtils::Miniperl;
    writemain(@directories);
    # or
    writemain($fh, @directories);
    # or
    writemain(\$filename, @directories);

=head1 DESCRIPTION

C<writemain()> takes an argument list of zero or more directories
containing archive
libraries that relate to perl modules and should be linked into a new
perl binary. It writes a corresponding F<miniperlmain.c> or F<perlmain.c>
file that
is a plain C file containing all the bootstrap code to make the
modules associated with the libraries available from within perl.
If the first argument to C<writemain()> is a reference to a scalar it is
used as the filename to open for output. Any other reference is used as
the filehandle to write to. Otherwise output defaults to C<STDOUT>.

The typical usage is from within perl's own Makefile (to build
F<perlmain.c>) or from F<regen/miniperlmain.pl> (to build miniperlmain.c).
So under normal circumstances you won't have to deal with this module
directly.

=head1 SEE ALSO

L<ExtUtils::MakeMaker>

=cut

# ex: set ts=8 sts=4 sw=4 et:
