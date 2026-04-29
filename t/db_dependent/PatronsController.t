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

use Test::More tests => 1;
use Test::Mojo;

use Koha::Database;
use Koha::DateUtils qw(dt_from_string);

use t::lib::Mocks;
use t::lib::TestBuilder;
use t::lib::Mocks::INNReach;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

my $ill_reqs_class;
if ( C4::Context->preference('Version') ge '24.050000' ) {
    $ill_reqs_class = "Koha::ILL::Requests";
} else {
    $ill_reqs_class = "Koha::Illrequests";
}

t::lib::Mocks::mock_preference( 'RESTBasicAuth', 1 );

my $t = Test::Mojo->new('Koha::REST::V1');

subtest 'verifypatron() nonLocalLoans tests' => sub {
    plan tests => 2;

    subtest 'nonLocalLoans with no ILL requests' => sub {
        plan tests => 3;

        $schema->storage->txn_begin;

        my $centralCode = 'd2ir';
        my $password    = 'thePassword123';
        my $user        = add_superlibrarian($password);
        my $userid      = $user->userid;

        my $library  = $builder->build_object( { class => 'Koha::Libraries' } );
        my $category = $builder->build_object( { class => 'Koha::Patron::Categories' } );
        my $itemtype = $builder->build_object( { class => 'Koha::ItemTypes' } );

        my $plugin = t::lib::Mocks::INNReach->new(
            {
                library  => $library,
                category => $category,
                itemtype => $itemtype,
                config   => {
                    $centralCode => {
                        require_patron_auth => 'false',
                    }
                }
            }
        );

        my $patron = $builder->build_object(
            {
                class => 'Koha::Patrons',
                value => {
                    categorycode => $category->categorycode,
                    branchcode   => $library->branchcode,
                }
            }
        );

        my $params = {
            visiblePatronId  => $patron->cardnumber,
            patronAgencyCode => 'test2',
            patronName       => 'Test Patron',
        };

        $t->post_ok( "//$userid:$password\@/api/v1/contrib/innreach/v2/circ/verifypatron" =>
                { 'X-From-Code' => $centralCode } => json => $params )
            ->status_is(200)
            ->json_is( '/patronInfo/nonLocalLoans' => 0 );

        $schema->storage->txn_rollback;
    };

    subtest 'nonLocalLoans counts only borrowing statuses' => sub {
        plan tests => 3;

        $schema->storage->txn_begin;

        my $centralCode = 'd2ir';
        my $password    = 'thePassword123';
        my $user        = add_superlibrarian($password);
        my $userid      = $user->userid;

        my $library  = $builder->build_object( { class => 'Koha::Libraries' } );
        my $category = $builder->build_object( { class => 'Koha::Patron::Categories' } );
        my $itemtype = $builder->build_object( { class => 'Koha::ItemTypes' } );

        my $plugin = t::lib::Mocks::INNReach->new(
            {
                library  => $library,
                category => $category,
                itemtype => $itemtype,
                config   => {
                    $centralCode => {
                        require_patron_auth => 'false',
                    }
                }
            }
        );

        my $patron = $builder->build_object(
            {
                class => 'Koha::Patrons',
                value => {
                    categorycode => $category->categorycode,
                    branchcode   => $library->branchcode,
                }
            }
        );

        # Borrowing statuses that should be counted
        my @counted_statuses =
            qw(B_ITEM_REQUESTED B_ITEM_SHIPPED B_ITEM_RECEIVED B_ITEM_RECALLED B_ITEM_CLAIMED_RETURNED);

        # Statuses that should NOT be counted
        my @ignored_statuses = qw(O_ITEM_REQUESTED O_ITEM_SHIPPED B_ITEM_RETURNED COMPLETED);

        for my $status ( @counted_statuses, @ignored_statuses ) {
            $builder->build_object(
                {
                    class => $ill_reqs_class,
                    value => {
                        backend           => 'INNReach',
                        status            => $status,
                        borrowernumber    => $patron->borrowernumber,
                        branchcode        => $library->branchcode,
                        biblio_id         => undef,
                        deleted_biblio_id => undef,
                        completed         => undef,
                        medium            => undef,
                        orderid           => undef,
                    }
                }
            );
        }

        my $params = {
            visiblePatronId  => $patron->cardnumber,
            patronAgencyCode => 'test2',
            patronName       => 'Test Patron',
        };

        $t->post_ok( "//$userid:$password\@/api/v1/contrib/innreach/v2/circ/verifypatron" =>
                { 'X-From-Code' => $centralCode } => json => $params )
            ->status_is(200)
            ->json_is( '/patronInfo/nonLocalLoans' => scalar @counted_statuses );

        $schema->storage->txn_rollback;
    };
};

sub add_superlibrarian {
    my ($password) = @_;
    my $patron = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 1 }
        }
    );
    $password //= 'thePassword123';
    $patron->set_password( { password => $password, skip_validation => 1 } );
    $patron->discard_changes;
    return $patron;
}
