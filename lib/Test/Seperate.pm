package Test::Seperate;
use strict;
use warnings;

#{{{ POD

=pod

=head1 NAME

Test::Seperate - Seperate sets of tests from others to prevent bleeding between tests, or to restore EVERYTHING between tests.

=head1 DESCRIPTION

Test::Seperate allows you to run tests seperately. This is useful for returning
to a known or pristine state between tests. Test::Seperate seperates tests into
different forked processes. You can do whatever you want in a test set without
fear that something you do will effect a test in another set.

=head1 SYNOPSYS

    #!/usr/bin/perl
    use strict;
    use warnings;

    use Test::More tests => 5;
    # 'all' as first param is essentially 'Test::More' => \@Test::More::EXPORT;
    # and will make all the exported functions in Test::More work in forked
    # processes.
    use Test::Seperate 'all', 'Test::Something' => [qw/ something_ok nothing_ok /];

    # Counts as 2 tests, the ok() within, and seperate_tests() itself.
    seperate_tests { ok( 1, "a test that has been seperated" ) } "A seperate test";

    # Define a new package w/ a package variable inside a seperate test
    seperate_tests {
        {
            package Test::Seperate::__Test;
            our $TEST = 1;
        }

        is( $Test::Seperate::__Test::TEST, 1, "Found package variable defined in seperate test while in seperate test scope" );
    } "Package defined in seperate test";

    # Package from seperate test does not bleed out.
    ok(
        !defined( $Test::Seperate::__Test::TEST ),
        "Package variable defined in seperate test no longer defined outside of seperate test"
    );

=head1 HOW IT WORKS

Test::Seperate will fork a new process when you run seperate_tests(). Before
forking a pipe will be opened through which the processes may communicate.
Within the child process all Test::More subs will be overriden to store their
parameters instead of running their checks. When the child is finished it sends
the information to the parent via the open pipe. The parent will run the
appropreat tests using the values provided from the child.

=head1 EXPORTED FUNCTIONS

=over 4

=cut

#}}}

use Exporter;
use Test::More;
use Data::Dumper;

our @EXPORT = qw/seperate_tests make_test_fork_safe make_tests_fork_safe/;
our $SEPERATOR = 'EODATA';
our $VERSION = "0.002";
our $STATE = 'parent';
our %OVERRIDES;
pipe( READ, WRITE ) || die( $! );

sub import {
    my ( $class, @params ) = @_;
    my ( $caller ) = caller();
    if ( @params and $params[0] eq 'all' ) {
        shift( @params );
        make_tests_fork_safe( 'Test::More' => \@Test::More::EXPORT, 'caller' => $caller );
    }
    make_tests_fork_safe( @params, 'caller' => $caller ) if @params;
    pop( @_ ) while ( @_ > 1 );
    goto &Exporter::import;
}

=item seperate_tests( sub { ok( 1, 'test' ); ... }, $message )

Runs the sub in a forked process. Overrides any Test::More subs so that they
will be run in the parent when the child exists.

Note: When a test fails it will say the failure occured in Test/Seperate.pm,
however a seperate diagnostics message will be printed with the correct
filename and line number.

=cut

sub seperate_tests(&;$) {
    my ($sub, $message) = @_;
    my ( $caller ) = caller();

    if ( my $pid = fork()) {
        my $data = _read();
        waitpid( $pid, 0 );
        my $out = !$?;
        _run_tests( $data );
        ok( $out, $message );
    }
    else {
        $STATE = 'child';
        $sub->();
        _write( $SEPERATOR );
        exit;
    }
}

=item make_test_fork_safe( $package, $sub )

Make $sub from $package work in a forked process.

=cut

sub make_test_fork_safe {
    my ( $package, $sub, $caller ) = @_;
    ( $caller ) = caller() unless $caller;
    my $code;
    unless ( $code = $OVERRIDES{ $package }{ $sub }{ override } ) {
        {
            no strict 'refs';
            $OVERRIDES{ $package }{ $sub }{ original } = \&{ $package . '::' . $sub };
        }
        $code = sub {
            # Run original if we are not in a child state.
            goto &{ $OVERRIDES{ $package }{ $sub }{ original }} if $STATE eq 'parent';

            my @params = @_;
            my ( $caller, $filename, $line ) = caller();
            _write( Dumper([
                [ $package, $sub ],
                {
                    'caller' => {
                        'package' => $caller,
                        filename  => $filename,
                        line      => $line,
                    },
                    params => \@params
                }
            ]));
            "Test delayed";
        };
        $OVERRIDES{ $package }{ $sub }{ override } = $code;
        _do_override( $package, $sub, $code );
    }
    _do_override( $caller, $sub, $code ) if $caller and $caller ne __PACKAGE__;
}

=item_tests_fork_safe( $package => \@subs, $package2 => \@subs2 )

Same as make_test_fork_safe except for many subs/packages.

=cut

sub make_tests_fork_safe {
    my %params = @_;
    my ( $caller ) = delete( $params{ 'caller' } ) || caller();
    while ( my ( $package, $subs ) = each %params ) {
        make_test_fork_safe( $package, $_, $caller ) for @$subs;
    }
}

sub _run_tests {
    my ( $tests ) = @_;
    {
        no strict;
        $tests = [ map {
            $out = eval $_;
            die $@ if $@;
            $out
        } split( $SEPERATOR, $tests )];
    }

    for my $test ( @$tests ) {
        my ( $psub, $data ) = @$test;
        my ( $package, $sub ) = @$psub;
        my ( $caller, $params ) = @$data{qw/caller params/};
        no strict 'refs';
        eval { $OVERRIDES{ $package }{ $sub }{ original }->( @$params )}
            || diag( "Failure was at: " . $caller->{ filename } . " line: " . $caller->{ line });
        diag $@ if $@;
    }
    return $tests;
}

sub _do_override {
    my ( $package, $sub, $code ) = @_;
    no strict 'refs';
    no warnings 'redefine';
    no warnings 'prototype';
    return unless defined( &{ $package . '::' . $sub });
    *{ $package . '::' . $sub } = $code;
}

sub _read {
    local $/ = $SEPERATOR;
    my $data = <READ>;
    return $data;
}

sub _write {
    print WRITE $_ for @_;
    1;
}

1;

__END__

=back

=head1 SEE ALSO

L<Test::Fork>
L<Test::MultiFork>
L<Test::SharedFork>

=head1 AUTHORS

Chad Granum L<exodist7@gmail.com>

=head1 COPYRIGHT

Copyright (C) 2009 Chad Granum

Test-Seperate is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation; either version 2 of the License, or (at your option) any
later version.

Test-Seperate is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
