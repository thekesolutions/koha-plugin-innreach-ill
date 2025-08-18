#!/usr/bin/perl

# This file is part of the INNReach plugin
#
# The INNReach plugin is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# The INNReach plugin is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with The INNReach plugin; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use Test::More;
use File::Spec;
use File::Find;

# Suppress redefinition warnings during module loading tests
# These warnings are common in plugin environments where modules
# may be loaded multiple times during testing
no warnings 'redefine';

my %loaded_modules;

find(
    {
        bydepth  => 1,
        no_chdir => 1,
        wanted   => sub {
            my $m = $_;
            return unless $m =~ s/[.]pm$//;
            $m =~ s{^.*/Koha/}{Koha/};
            $m =~ s{/}{::}g;
            
            # Skip if already loaded to prevent redefinition
            return if $loaded_modules{$m};
            $loaded_modules{$m} = 1;
            
            use_ok($m) || BAIL_OUT("***** PROBLEMS LOADING FILE '$m'");
        },
    },
    '.'
);

done_testing();
