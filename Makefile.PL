#!/usr/bin/env perl
use strict;
use warnings;
use inc::Module::Install;

perl_version '5.008';
license 'gpl';
all_from 'lib/Test/Seperate.pm';

requires (
    'Test::More' => 0,
);

WriteAll;

