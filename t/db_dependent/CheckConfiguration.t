#!/usr/bin/env perl

# Copyright 2026 Theke Solutions
#
# This file is part of The INNReach plugin.
#
# The INNReach plugin is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# The INNReach plugin is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with The INNReach plugin; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use Test::More tests => 1;

use C4::Context;
use Koha::Database;
use Koha::Patrons;

use t::lib::TestBuilder;
use t::lib::Mocks;
use t::lib::Mocks::INNReach;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

subtest 'check_configuration() anonymization tests' => sub {

    plan tests => 5;

    subtest 'AnonymousPatron not set, nobody using privacy = never' => sub {

        plan tests => 1;

        $schema->storage->txn_begin;

        my $plugin = build_plugin();

        neutralize_existing_privacy_never();
        t::lib::Mocks::mock_preference( 'AnonymousPatron', q{} );

        is(
            error_count( $plugin, 'anonymous_patron_not_set' ),
            0, 'No error reported when anonymization is never triggered'
        );

        $schema->storage->txn_rollback;
    };

    subtest 'AnonymousPatron not set, some patron uses privacy = never' => sub {

        plan tests => 1;

        $schema->storage->txn_begin;

        my $plugin = build_plugin();

        $builder->build_object( { class => 'Koha::Patrons', value => { privacy => 2 } } );
        t::lib::Mocks::mock_preference( 'AnonymousPatron', q{} );

        is( error_count( $plugin, 'anonymous_patron_not_set' ), 1, 'Unset AnonymousPatron reported' );

        $schema->storage->txn_rollback;
    };

    subtest 'AnonymousPatron points at a patron that does not exist' => sub {

        plan tests => 2;

        $schema->storage->txn_begin;

        my $plugin = build_plugin();

        $builder->build_object( { class => 'Koha::Patrons', value => { privacy => 2 } } );

        my $deleted_patron = $builder->build_object( { class => 'Koha::Patrons' } );
        my $borrowernumber = $deleted_patron->borrowernumber;
        $deleted_patron->delete;

        t::lib::Mocks::mock_preference( 'AnonymousPatron', $borrowernumber );

        is( error_count( $plugin, 'anonymous_patron_not_found' ), 1, 'Dangling AnonymousPatron reported' );
        is( error_count( $plugin, 'anonymous_patron_not_set' ),   0, 'Not also reported as unset' );

        $schema->storage->txn_rollback;
    };

    subtest 'AnonymousPatron correctly set' => sub {

        plan tests => 2;

        $schema->storage->txn_begin;

        my $plugin = build_plugin();

        $builder->build_object( { class => 'Koha::Patrons', value => { privacy => 2 } } );

        my $anonymous_patron = $builder->build_object( { class => 'Koha::Patrons' } );
        t::lib::Mocks::mock_preference( 'AnonymousPatron', $anonymous_patron->borrowernumber );

        is( error_count( $plugin, 'anonymous_patron_not_set' ),   0, 'No unset error' );
        is( error_count( $plugin, 'anonymous_patron_not_found' ), 0, 'No dangling error' );

        $schema->storage->txn_rollback;
    };

    subtest 'partners_category defaulting to privacy = never' => sub {

        plan tests => 2;

        $schema->storage->txn_begin;

        my $category = $builder->build_object(
            {
                class => 'Koha::Patron::Categories',
                value => { default_privacy => 'never' }
            }
        );

        my $plugin = build_plugin( { category => $category } );

        # No patron has privacy = never, but every partner patron created for this
        # central server will, so the AnonymousPatron setup still matters
        neutralize_existing_privacy_never();
        t::lib::Mocks::mock_preference( 'AnonymousPatron', q{} );

        is( error_count( $plugin, 'partners_category_privacy_never' ), 1, 'Partner category reported' );
        is( error_count( $plugin, 'anonymous_patron_not_set' ), 1, 'Unset AnonymousPatron reported because of it' );

        $schema->storage->txn_rollback;
    };
};

=head2 Helper methods

=head3 build_plugin

    my $plugin = build_plugin( [ { category => $category } ] );

Returns a configured plugin instance.

=cut

sub build_plugin {
    my ($params) = @_;

    $params //= {};

    return t::lib::Mocks::INNReach->new(
        {
            library  => $builder->build_object( { class => 'Koha::Libraries' } ),
            category => $params->{category} // $builder->build_object( { class => 'Koha::Patron::Categories' } ),
            itemtype => $builder->build_object( { class => 'Koha::ItemTypes' } ),
        }
    );
}

=head3 neutralize_existing_privacy_never

    neutralize_existing_privacy_never();

Clears any pre-existing privacy = 'never' patron from the test database, so
subtests can assert on the "nobody is using it" case. Goes straight to the
resultset to avoid running Koha::Patron->store on the whole table.

=cut

sub neutralize_existing_privacy_never {
    return $schema->resultset('Borrower')->search( { privacy => 2 } )->update( { privacy => 1 } );
}

=head3 error_count

    my $count = error_count( $plugin, $code );

Returns how many times I<$code> shows up in the configuration check results.

=cut

sub error_count {
    my ( $plugin, $code ) = @_;

    return scalar grep { $_->{code} eq $code } @{ $plugin->check_configuration };
}
