#!/usr/bin/perl

#
# Copyright 2019 Theke Solutions
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# This program comes with ABSOLUTELY NO WARRANTY;

use Modern::Perl;

use Data::Printer colored => 1;
use Getopt::Long;
use Koha::Plugin::Com::Theke::INNReach::Contribution;

binmode(STDOUT,':encoding(utf8)');

my $locations;
my $item_types;
my $patron_types;
my $all;

my $result = GetOptions(
    'locations'    => \$locations,
    'item_types'   => \$item_types,
    'patron_types' => \$patron_types,
    'all'          => \$all,
);

unless ($result) {
    print_usage();
    die "Not sure what wen't wrong";
}

unless ( $locations or $item_types or $patron_types or $all ) {
    print_usage();
    exit 0;
}

sub print_usage {
    print <<_USAGE_;

    C'mon! Valid options are

    --locations        Fetch locations data
    --item_types       Fetch central item types
    --patron_types     Fetch central patron types
    --all              Fetch all the data from the central servers

_USAGE_
}

if ( $all ) {
    $locations    = 1;
    $item_types   = 1;
    $patron_types = 1;
}

my $response;
my $contribution = Koha::Plugin::Com::Theke::INNReach::Contribution->new;

my @central_servers = @{ $contribution->config->{centralServers} };

if ( $locations ) {
    print STDOUT "# Locations:\n";
    foreach my $central_server (@central_servers) {
        print STDOUT "## $central_server:\n";
        $response = $contribution->get_locations_list({ centralServer => $central_server });
        foreach my $location ( @{ $response } ) {
            print STDOUT p( $location );
        }
    }
}

if ( $item_types ) {
    print STDOUT "# Item types:\n";
    foreach my $central_server (@central_servers) {
        print STDOUT "## $central_server:\n";
        $response = $contribution->get_central_item_types({ centralServer => $central_server });
        foreach my $item_type ( @{ $response } ) {
            print STDOUT p( $item_type );
        }
    }
}

if ( $patron_types ) {
    print STDOUT "# Patron types:\n";
    foreach my $central_server (@central_servers) {
        print STDOUT "## $central_server:\n";
        $response = $contribution->get_central_patron_types_list({ centralServer => $central_server });
        foreach my $patron_type ( @{ $response } ) {
            print STDOUT p( $patron_type );
        }
    }
}

1;
