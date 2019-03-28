# koha-plugin-innreach

This project implements a plugin integrating Koha with the INNReach ILL service.

## WIP
This project is work-in-progress

## Goal
When finished, this plugin will implement:
* The required endpoints for INNReach -> Koha communication
* Implement a [Koha ILL backend](https://wiki.koha-community.org/wiki/ILL_backends) that does the required Koha -> INNReach communication too

## Problems to solve
* We need to hook all biblio and items CRUD operations to report back to the INNReach Central Server (contributing records).
This could be easily done in rebuild_zebra.pl, but we might need a separate server.

## Endpoints covered by the spec

```
    POST /api/v1/contrib/innreach/v2/circ/verifypatron
    POST /api/v1/contrib/innreach/v2/getbibrecord/{bibId}/{centralCode}
    POST /api/v1/contrib/innreach/v2/circ/itemhold/{trackingId}/{centralCode}
    PUT  /api/v1/contrib/innreach/v2/circ/intransit/{trackingId}/{centralCode}
    POST /api/v1/contrib/innreach/v2/circ/patronhold/{trackingId}/{centralCode}
    PUT  /api/v1/contrib/innreach/v2/circ/ownerrenew/{trackingId}/{centralCode}
    PUT  /api/v1/contrib/innreach/v2/circ/itemshipped/{trackingId}/{centralCode}
    PUT  /api/v1/contrib/innreach/v2/circ/itemreceived/{trackingId}/{centralCode}
    PUT  /api/v1/contrib/innreach/v2/circ/finalcheckin/{trackingId}/{centralCode}
    PUT  /api/v1/contrib/innreach/v2/circ/borrowerrenew/{trackingId}/{centralCode}
    PUT  /api/v1/contrib/innreach/v2/circ/cancelrequest/{trackingId}/{centralCode}
    PUT  /api/v1/contrib/innreach/v2/circ/cancelitemhold/{trackingId}/{centralCode}
    PUT  /api/v1/contrib/innreach/v2/circ/claimsreturned/{trackingId}/{centralCode}
    PUT  /api/v1/contrib/innreach/v2/circ/transferrequest/{trackingId}/{centralCode}
    PUT  /api/v1/contrib/innreach/v2/circ/receiveunshipped/{trackingId}/{centralCode}
    PUT  /api/v1/contrib/innreach/v2/circ/returnuncirculated/{trackingId}/{centralCode} 
```

## Configuration structure

```
    api_key: a_key
    api_secret: a_secret
    centralServers:
        - d2ir
    library_to_agency:
        CPL: code1
        MPL: code2
    localServerCode: mykoha
```

## Install
Download the latest _.kpz_ file from the [releases](https://github.com/thekesolutions/koha-plugin-innreach/releases) page.
Install it as any other plugin following the general [plugin install instructions](https://wiki.koha-community.org/wiki/Koha_plugins).
