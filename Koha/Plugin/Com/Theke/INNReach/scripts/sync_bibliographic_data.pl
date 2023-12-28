#/usr/bin/perl

# Copyright 2023 Theke Solutions
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

use Getopt::Long;
use List::MoreUtils qw(any);

use Koha::Plugin::Com::Theke::INNReach::Contribution;

use C4::Context;
use Koha::Biblios;

use Koha::Plugin::Com::Theke::INNReach;
use Koha::Plugin::Com::Theke::INNReach::Contribution;

binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

my $biblio_id;
my $central_server;
my $exclude_items;
my $help;
my $limit;
my $noout;
my $where;

my $result = GetOptions(
    'biblio_id=s'      => \$biblio_id,
    'central_server=s' => \$central_server,
    'exclude_items'    => \$exclude_items,
    'help'             => \$help,
    'limit=i'          => \$limit,
    'noout'            => \$noout,
    'where=s'          => \$where,
);

unless ($result) {
    print_usage();
    say "Not sure what wen't wrong";
    exit 1;
}

if ($help) {
    print_usage();
    exit 0;
}

unless ($central_server) {
    print_usage();
    say "--central_server is missing (mandatory)";
    exit 1;
}

if ( $biblio_id and $where ) {
    print_usage();
    say "--biblio_id and --where are mutually exclussive";
    exit 1;
}

sub print_usage {
    print <<_USAGE_;

This script takes care of sinchronizing biblios and items with the specified central
server, based on the configuration. It can be run to acknowledge configuration changes
or even for an initial contribution.

If you want more fine-grained control (e.g. force contribution of records that wouldn't
be contributed because of the configuration) use contribute_data.pl

Options:

    --central_server       Contribute to the specified central server (mandatory)
    --where "condition"    Conditions on `biblio` table columns (_SQL_ `WHERE` syntax)
    --biblio_id "id"       A particular biblionumber specified.

    --noout                No output
    --help                 This help

_USAGE_
}

my $plugin       = Koha::Plugin::Com::Theke::INNReach->new;
my $contribution = Koha::Plugin::Com::Theke::INNReach::Contribution->new( { plugin => $plugin } );

my $query      = {};
my $attributes = {};

if ($biblio_id) {
    $query = { biblionumber => $biblio_id };
} elsif ($where) {    # where
    $query = \[$where];
}

$attributes = { rows => $limit }
    if $limit;

my $biblios = Koha::Biblios->search( $query, $attributes );

while ( my $biblio = $biblios->next ) {

    print STDOUT "Record: " . $biblio->id . "\n"
        unless $noout;

    if ( $contribution->is_bib_contributed( { biblio_id => $biblio->id, central_server => $central_server } ) ) {
        $contribution->decontribute_bib(
            {
                bibId         => $biblio->id,
                centralServer => $central_server,
            }
        );

        print STDOUT "\t* decontributed\n"
            unless $noout;
    }

    my $contributable_items = $contribution->filter_items_by_contributable(
        {
            items          => $biblio->items,
            central_server => $central_server
        }
    );

    if ( $contributable_items->count > 0
        || !$plugin->configuration->{$central_server}->{contribution}->{exclude_empty_biblios} )
    {

        $plugin->schedule_task(
            {
                action         => 'create',
                central_server => $central_server,
                object_id      => $biblio->id,
                object_type    => 'biblio',
                status         => 'queued',
            }
        );

        print STDOUT "\t* contributed\n"
            unless $noout;

        if ( $contributable_items->count > 0 ) {
            print STDOUT "\t* items:\n"
                unless $noout;

            while ( my $item = $contributable_items->next ) {

                $plugin->schedule_task(
                    {
                        action         => 'create',
                        central_server => $central_server,
                        object_id      => $item->id,
                        object_type    => 'item',
                        status         => 'queued',
                    }
                );

                print STDOUT "\t\t * " . $item->id . " (contribute)\n"
                    unless $noout;
            }
        }
    }
}

1;

