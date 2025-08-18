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

# Test only the main plugin modules that should be loaded directly
# Background jobs and command modules are loaded by the plugin system
# and shouldn't be tested with use_ok as they may cause redefinition warnings

my @modules_to_test = (
    'Koha::Plugin::Com::Theke::INNReach',
    'Koha::Illbackends::INNReach::Base',
    'Koha::Plugin::Com::Theke::INNReach::BibliosController',
    'Koha::Plugin::Com::Theke::INNReach::CircController',
    'Koha::Plugin::Com::Theke::INNReach::OAuth2',
    'Koha::Plugin::Com::Theke::INNReach::PatronsController',
    'Koha::Plugin::Com::Theke::INNReach::Utils',
    'Koha::Plugin::Com::Theke::INNReach::Exceptions',
    'Koha::Plugin::Com::Theke::INNReach::Contribution',
    'Koha::Plugin::Com::Theke::INNReach::Normalizer',
);

# Test each module
foreach my $module (@modules_to_test) {
    use_ok($module) || BAIL_OUT("***** PROBLEMS LOADING MODULE '$module'");
}

done_testing();
