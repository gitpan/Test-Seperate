#!/usr/bin/perl
use strict;
use warnings;

use Test::More tests => 8;

use_ok 'Test::Seperate';
use Test::Seperate;

seperate_tests { ok( 1, "a test that has been seperated" ) } "A seperate test";

seperate_tests {
    {
        package Test::Seperate::__Test;
        our $TEST = 1;
    }

    is( $Test::Seperate::__Test::TEST, 1, "Found package variable defined in seperate test while in seperate test scope" );
} "Package defined in seperate test";

ok(
    !defined( $Test::Seperate::__Test::TEST ),
    "Package variable defined in seperate test no longer defined outside of seperate test"
);

my $original_ok = \&ok;
seperate_tests { ok( $original_ok != \&ok, "ok() was overriden" )} "tests for _override_test_more()";
