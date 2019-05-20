# koha-plugin-innreach

This project implements a plugin integrating Koha with the INN-Reach ILL service.

## WIP
This project is work-in-progress

## Goal
When finished, this plugin will implement:
* The required endpoints for INN-Reach -> Koha communication
* Implement a [Koha ILL backend](https://wiki.koha-community.org/wiki/ILL_backends) that does the required Koha -> INNReach communication too

## Problems to solve
* We need to hook all biblio and items CRUD operations to report back to the INNReach Central Server (contributing records).
This could be easily done in rebuild_zebra.pl, but we might need a separate server.

# Implemented

## Record/data contribution

The plugin implements methods that cover all data contribution options.

### Implemented required endpoints
```
    POST /api/v1/contrib/innreach/v2/getbibrecord/{bibId}/{centralCode}
```

TODO: They aren't yet packed into a set of maintenance scripts/daemons that keep
things up-to-date. _Koha::Plugin::Com::Theke::INNReach::Contribution_ implements
all documented interactions.

## Owning site

This plugin implements the full squence diagram included in the INN-Reach spec.
It is done in the form of a Koha ILL backend.

Some transitions are triggered through the UI (through the ILL module), and others
by API interactions.

### Implemented required endpoints

```
    POST /api/v1/contrib/innreach/v2/circ/itemhold/{trackingId}/{centralCode}
    PUT  /api/v1/contrib/innreach/v2/circ/itemreceived/{trackingId}/{centralCode}
    PUT  /api/v1/contrib/innreach/v2/circ/intransit/{trackingId}/{centralCode}
    PUT  /api/v1/contrib/innreach/v2/circ/cancelitemhold/{trackingId}/{centralCode}
```

## Borrowing site

This plugin implements the full squence diagram included in the INN-Reach spec.
It is done in the form of a Koha ILL backend.

Some transitions are triggered through the UI (through the ILL module), and others
by API interactions.

### Implemented required endpoints

```
    POST /api/v1/contrib/innreach/v2/circ/verifypatron
    POST /api/v1/contrib/innreach/v2/circ/patronhold/{trackingId}/{centralCode}
    PUT  /api/v1/contrib/innreach/v2/circ/itemshipped/{trackingId}/{centralCode}
    PUT  /api/v1/contrib/innreach/v2/circ/finalcheckin/{trackingId}/{centralCode}
```

# TODO

The following endpoints (taking out cancelrequest) have no clear fit in the documented
flows and require further conversations to get implemented properly.

```
    PUT  /api/v1/contrib/innreach/v2/circ/ownerrenew/{trackingId}/{centralCode}
    PUT  /api/v1/contrib/innreach/v2/circ/borrowerrenew/{trackingId}/{centralCode}
    PUT  /api/v1/contrib/innreach/v2/circ/cancelrequest/{trackingId}/{centralCode}
    PUT  /api/v1/contrib/innreach/v2/circ/claimsreturned/{trackingId}/{centralCode}
    PUT  /api/v1/contrib/innreach/v2/circ/transferrequest/{trackingId}/{centralCode}
    PUT  /api/v1/contrib/innreach/v2/circ/receiveunshipped/{trackingId}/{centralCode}
    PUT  /api/v1/contrib/innreach/v2/circ/returnuncirculated/{trackingId}/{centralCode} 
```

## Configuration structure

```
    centralServers:
        - d2ir
    api_base_url: https://rssandbox-api.iii.com
    client_id: a_client_id
    client_secret: a_client_secret
    localServerCode: koha1
    mainAgency: code2
    library_to_location:
        CPL: code1
        MPL: code2
    local_to_central_itype:
        BK: 200
        CF: 201
        CR: 200
        MP: 200
        MU: 201
        MX: 201
        REF: 202
        VM: 201
```

## Install
Download the latest _.kpz_ file from the [releases](https://github.com/thekesolutions/koha-plugin-innreach/releases) page.
Install it as any other plugin following the general [plugin install instructions](https://wiki.koha-community.org/wiki/Koha_plugins).
