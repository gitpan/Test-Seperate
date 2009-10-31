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
    use Test::Seperate;

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

use base 'Exporter';
use Test::More;
use Data::Dumper;

our @EXPORT = qw/seperate_tests/;
our $SEPERATOR = 'EODATA';
our $VERSION = "0.001";

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
    pipe( READ, WRITE );

    if ( my $pid = fork()) {
        local $/ = $SEPERATOR;
        my $tests = <READ>;
        waitpid( $pid, 0 );
        my $out = !$?;
        _run_tests( $tests );
        ok( $out, $message );
    }
    else {
        my $tests = {};
        _override_test_more($caller, $tests);
        $sub->();
        print WRITE Dumper( $tests );
        print WRITE 'EODATA';
        close( WRITE );
        exit;
    }
    close( READ );
    close( WRITE );
}

sub _override_test_more {
    my ( $caller, $tests ) = @_;
    my @subs = @Test::More::EXPORT;
    for my $sub ( @subs ) {
        no strict 'refs';
        no warnings 'redefine';
        no warnings 'prototype';
        *{ $caller . '::' . $sub } = sub {
            my @params = @_;
            my ( $package, $filename, $line ) = caller();
            $tests->{ $sub } ||= [];
            push @{ $tests->{ $sub }} => {
                'caller' => {
                    'package' => $package,
                    filename  => $filename,
                    line      => $line,
                },
                params => \@params
            };
        }
    }
}

sub _run_tests {
    my ( $tests ) = @_;
    $tests =~ s/$SEPERATOR//;
    {
        no strict;
        $tests = eval $tests;
        die( $@ ) if $@;
    }

    for my $sub ( keys %$tests ) {
        no strict 'refs';
        while ( my $test = shift( @{ $tests->{ $sub }})) {
            my ( $caller, $params ) = @$test{qw/caller params/};
            &$sub( @$params )
                || diag( "Failure was at: " . $caller->{ filename } . " line: " . $caller->{ line });
        }
    }
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
