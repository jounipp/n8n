# Outlook-synkronointi ja AI-validointi — tilannekuva ja päätökset

Tämä dokumentti kokoaa esiin nousseet havainnot ja sovitut periaatteet ennen toteutusta. Tavoitteena on varmistaa yhteinen ymmärrys backfillistä, delta-synkronoinnista ja nykyisten workflow’iden rooleista.

## Tilannekuva
- Noin 8600 viestiä luokiteltu vanhalla AI:lla kantaan, mutta Outlookissa ei vielä kategorioita/lippuja.
- Uusi AI-malli: hybrid rules + prompt caching, vielä testaamatta.
- Delta-linkki on vanhentunut; halutaan webhook-pohjainen, reaaliaikainen malli ilman turhia schedule-ajoja.
- Jatkossa vain Saapuneet-kansiota deltataan; riski paisumisesta → tarvitaan siivous/arkistointi-säännöt.
- Nykyiset n8n-workflow’t toimivat erillisinä; puuttuu yhdistävä ohjausketju (webhook → fetch → validate → sync).
- “Outlook Orchestrator” on vain malliksi; ei käytetä projektissa.
- Erillistä Outlook Gateway -workflow’ta ei ylläpidetä; Gateway-logiikka on integroitu “Outlook Validate Analyse” -workflow’hun (ks. dokumentit).

## Nykyinen skeema ja käyttö
- Delta-tila on mallinnettu ja käytössä: `outlook.delta_state` (mm. `delta_link`, `next_link`, `sync_status`, `items_processed`, `folder_id`, `folder_name`).
- Sähköpostien Outlook-tila peilataan `outlook.emails_ingest`-tauluun (mm. `categories`, `flag_status`, `parent_folder_id`).
- AI-analyysit ja päätökset:
  - `outlook.ai_analysis_log`: analyysitapahtumat.
  - `outlook.action_decisions`: päätökset ja synkkitila (`sync_status`, `synced_to_outlook_at`, `outlook_state_snapshot`).

## Päätökset
- Ei uutta backfill-taulua: backfill ajetaan kertaluonteisesti ja idempotentisti hyödyntäen `action_decisions` + `emails_ingest`.
  - Valintakriteeri: viestit, joilla on päätös/analyysi, mutta ei `synced_to_outlook_at` tai `sync_status != 'synced'`.
  - PATCH Outlookiin (kategoriat/liput) batch-koossa (esim. 20/pyyntö), päivitä `action_decisions` ja peilaa `emails_ingest`.
- Validate-työjonot eivät käsittele jo analysoituja viestejä.
  - Uudet viestit → Validate-ketju (Select → Analyse) ja sen jälkeen Sync OL (+ Sync DB).
  - Vanhoihin (jo analysoituihin) viesteihin kohdistuvat muutokset → pelkkä synkka (ei Validatea).
- Käyttäjän Outlookissa tekemää muutosta vanhaan viestiin ei ylikirjoiteta.
  - Merkitään `action_decisions.sync_status = 'user_modified'` ja synkataan tila kantaan.
- Delta-synkronointi nojaa olemassa olevaan `outlook.delta_state`-tauluun.
  - Jos `delta_link` vanhenee (410), tehdään reset-aloitusdelta (rajataan `watermark`-periaatteella, esim. `last_modified_datetime`).
  - Ajastukset minimiin; webhook on ensisijainen. Kevyt “keeper” lisätään vain, jos hiljaisuus johtaa vanhenemiseen.
- Ei muutoksia nykyisten workflow’iden sisälogiikkaan.
  - Lisätään uudet ohuet wrapperit, jotka ohjaavat kutsuketjua `executeWorkflow`-nodeilla.
- Kategoriat: varmistetaan/luodaan puuttuvat `masterCategories` ennen viestikohtaisia PATCH-päivityksiä.

## Ylätasoarkkitehtuuri (wrapperit)
- Webhook Router (uusi):
  - Vastaanottaa Graph-notifikaatiot, validoi `clientState`, välittää tapahtumat Delta Runnerille.
- Delta Runner (uusi):
  - Hakee muutokset delta-linkillä (sivutus → uusi `@odata.deltaLink`).
  - Jokaiselle muutokselle tekee “Gate”-tarkistuksen kantaan:
    - Ei analysoitu → kutsuu nykyisiä workflow’ita: “Outlook Emails Fetch” (tai “Body Fetch”) → “Validate Select” → “Validate Analyse” → “Sync OL”; rinnalla “Sync DB”.
    - Analysoitu → ohittaa Validate-vaiheen ja tekee vain synkronoinnin (Outlook ↔ DB) päätöksen/snapshotin ehdoilla.
  - Huom: Gateway-logiikka sijaitsee osana “Outlook Validate Analyse” -workflow’ta (ei erillistä Gateway-workflow’ta).
- Backfill Runner (uusi):
  - Valitsee backfill-joukon (`synced_to_outlook_at IS NULL` tai `sync_status != 'synced'`).
  - PATCH batch’einä (n. 20/pyyntö), päivittää `action_decisions` ja peilaa `emails_ingest`.
- Notification Summary (myöhemmin):
  - Päivittäinen kooste (esim. finance + action required) sovittuun kanavaan.

## Workflow-roolit
- Olemassa olevat
  - Outlook Emails Fetch: hakee viestit/deltan sivutuksen mukaisesti, tallentaa metadatan ja päivittää `outlook.delta_state`a; käsittelee yksittäin.
  - Outlook Body Fetch: noutaa viestien rungon tarvittaessa yksittäisiin jatkokäsittelyihin.
  - Outlook Validate Select: ohjaa analyysiin menevät kohteet (valintalogiikka ennen syvää analyysiä).
  - Outlook Validate Analyse: sisältää Gateway-logiikan ja tekee analyysin; signaloi Sync OL -käynnistyksen analyysin jälkeen.
  - Outlook Sync OL: päivittää Outlookin tilan (kategoriat, liput, mahdolliset kansiosiirrot) päätösten perusteella.
  - Outlook Sync DB: peilaa Outlookin tilamuutokset kantaan (mm. categories, flag_status, folder-tiedot).
- Uudet wrapperit
  - Webhook Router: vastaanottaa Graph-notifikaatiot, validoi `clientState`, kutsuu Delta Runneria.
  - Delta Runner: ajaa delta-haun, tekee Gate-tarkistuksen (onko analysoitu) ja kutsuu olemassa olevia workflow’ita:
    - Ei analysoitu → Fetch → Validate Select → Validate Analyse → Sync OL (+ rinnalla Sync DB).
    - Analysoitu → ohittaa Validate-vaiheen ja tekee pelkän synkronoinnin (Outlook ↔ DB) päätösten/snapshotin mukaan.
  - Backfill Runner: batch-PATCH (esim. 20/pyyntö) vanhoille viesteille, joilla ei ole `synced_to_outlook_at` tai `sync_status != 'synced'`; päivittää `action_decisions` ja peilaa `emails_ingest`.

## Synkronointipolitiikka (vanha vs. uusi)
- Uudet viestit (ei riviä `ai_analysis_log` tai `action_decisions`): Validate-ketju → Sync OL + Sync DB → `sync_status='synced'`.
- Vanhat viestit (löytyy analyysi/päätös):
  - Käyttäjän Outlook-muutos: päivitä vain DB, aseta `user_modified`, älä ylikirjoita Outlookia.
  - Järjestelmän oma muutos (päätös/backfill): päivitä Outlook + DB, pidä `sync_status='synced'`.
  - Tarvittaessa re-analyysi vain eksplisiittisellä “reprocess”-lipulla.

## Turva, virheet ja näkyvyys
- Webhook: `clientState`-validointi, n8n-webhookin suojaus; älä käsittele dataa pelkästä notifikaatiosta, vaan tee erillinen haku.
- Rate limit / transient-virheet: käsittele 429/503 exponential backoffilla (kunnioita `Retry-After`).
- Delta 410/reset: tee uusi aloitusdelta käyttäen `watermark`-aikarajausta, ettei synny aukkoja.
- Lokitus ja mittarit: käsitellyt viestit/h, delta-sivujen määrä, virheiden taajuus, reset-tapahtumat.

## Inboxin siivous (suositus)
- Tavoite: Saapuneisiin jää vain toimenpiteitä vaativat viestit; muut siirretään sääntöjen perusteella (lähettäjä/aihe/kategoria/lippu) muihin kansioihin tai arkistoidaan.
- Synkronoi kansiomuutokset kantaan (`parent_folder_id`, `folder_name`).

## Avoimet asiat
- Päivittäisen yhteenvedon kanava ja muoto (sähköposti/Slack tms.).
- Tarvitaanko “keeper”-ajastus delta-linkin elossa pitämiseen vai riittävätkö notifikaatiot?
- `watermark`-kenttä: käytetäänkö `last_modified_datetime` vai muuta? (riippuu Outlook/Graph-kentistä).
- Gate-logiikan täsmällinen SQL (existence-check ai/arvosanat vs. päätös; idempotenssi ja suorituskyky).
- Backfillin batch-koko ja throttling (20/pyyntö alustava; tarkennetaan testissä).

## Liitteet
- Webhook-reitit työtilassa: `/webhook/graph/mail` (Gateway-logiikka Validate Analyse -workflow’ssa; ei erillistä `/webhook/outlook-gateway`).
- Käytetyt kredentiaalit: Graph Outlook, Postgres account, Anthropic account.
- Apuskriptit (työtilassa): `_analyze.ps1`, `_fix_metadata.ps1`, `_read_docx.ps1`.

## Backfill Steps (Gateway‑polku)
- Audit & normalisointi (DB)
  - Aja `db_outlook/backfill_audit.sql` audit‑osiot ja varmista flags/kategoria‑tila.
  - (Valinnainen) normalisoi `emails_ingest` vastaamaan päätöksiä ennen Outlook‑puskua.
- Päätösten muodostus (Gateway)
  - Workflow: `Outlook Backfill Decisions (Gateway)`
  - Lukee viestit ilman päätöstä ja kutsuu legacy‑Gatewayn (`Outlook Gateway Rules`).
  - Upserttaa `outlook.action_decisions` (sync_status='pending').
- Outlook‑PATCH backfill
  - Workflow: `Outlook Backfill PATCH (Categories/Flags)`
  - Valitsee pending‑päätökset, varmistaa että kategorioita/lippua on asetettavaksi, PATCHaa Microsoft Graphille, merkitsee `synced`.
- Jatkuvuus
  - Delta‑reititys: uudet → Validate‑ketju → Sync; analysoidut → pelkkä Sync (ei Validatea).
