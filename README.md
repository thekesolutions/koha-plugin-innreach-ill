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

## Install
Download the latest _.kpz_ file from the [releases](https://github.com/thekesolutions/koha-plugin-innreach/releases) page.
Install it as any other plugin following the general [plugin install instructions](https://wiki.koha-community.org/wiki/Koha_plugins).
