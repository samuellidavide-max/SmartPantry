# SmartPantry – SpesaOttimizzata

App mobile (Flutter) + backend (FastAPI, PostgreSQL/PostGIS) che confronta i prezzi dei supermercati vicini e ottimizza la lista della spesa: tutto in un negozio (scenario A) oppure diviso fra 2–3 negozi vicini (scenario B).

```
smartpantry-project/
├── docker-compose.yml      database + API in un comando
├── backend/                FastAPI, migrazioni SQL, ottimizzatore, pipeline scontrini, test
└── app/                    app Flutter (iOS e Android)
```

## 0. Provarla su Android senza installare Flutter (GitHub)

1. Crea un repository su GitHub (anche privato) e carica tutto il contenuto di questa cartella, compresa `.github/`.
2. GitHub compila l'app da solo (tab **Actions**, circa 10 minuti) e fa girare i test del backend.
3. Dal telefono apri la pagina **Releases** del repository, scarica `smartpantry-N.apk` e aprilo. Android chiederà di consentire l'installazione da "origini sconosciute".
4. All'apertura l'app cerca il server: inserisci l'indirizzo del backend (vedi sotto). Puoi impostarlo una volta per tutte nella variabile del repository `API_BASE_URL` (Settings › Secrets and variables › Actions › Variables).

Il backend deve comunque girare da qualche parte: sul tuo computer con Docker (punto 1, telefono sulla stessa Wi-Fi) oppure su un hosting online.

## 1. Avvia il backend (5 minuti)

Serve [Docker Desktop](https://www.docker.com/products/docker-desktop/).

```bash
cd smartpantry-project
docker compose up --build
```

- API: http://localhost:8000 · documentazione interattiva: http://localhost:8000/docs
- Le tabelle vengono create in automatico al primo avvio.
- I negozi demo si creano dall'app (vedi sotto) oppure da terminale, vicino alla posizione che vuoi:

```bash
docker compose exec api python -m app.seed --lat 45.4773 --lon 9.2050
```

Test del backend (facoltativo):

```bash
docker compose exec db psql -U postgres -c "CREATE DATABASE smartpantry_test"
docker compose exec -e DATABASE_URL=postgresql://postgres:smartpantry@db:5432/smartpantry_test api pytest -q
```

## 2. Avvia l'app

Serve [Flutter](https://docs.flutter.dev/get-started/install) (stabile 3.24 o successiva) con Android Studio e/o Xcode.

```bash
cd app
dart run tool/setup_platforms.dart   # crea android/ e ios/ e aggiunge permessi (posizione, fotocamera, rete locale)
flutter pub get
flutter run
```

### Dove trova il server

| Dove gira l'app | Indirizzo del backend |
| --- | --- |
| Emulatore Android | `http://10.0.2.2:8000` (predefinito) |
| Simulatore iOS | `http://localhost:8000` |
| Telefono vero (stessa Wi-Fi del computer) | `http://IP-DEL-COMPUTER:8000` (es. `http://192.168.1.20:8000`) |

L'indirizzo si imposta all'avvio con `flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000`, oppure dall'app: se il server non risponde compare una schermata per cambiarlo, e c'è anche in Profilo › Server.

### Primo avvio

1. Scegli la zona con il GPS o il CAP e il raggio.
2. Se in zona non ci sono negozi, tocca **"Crea negozi demo qui"**: il backend crea 9 supermercati demo attorno a te, con prezzi e promo.
3. Indica le carte fedeltà, crea una lista, poi **Confronta prezzi**.
4. Per provare Premium (scenario B completo, 10 km, liste illimitate): Profilo › Premium › *Attiva Premium (demo)*.
5. **Avvia spesa**, poi **Scansiona**: con l'OCR demo qualunque foto produce uno scontrino realistico del negozio della spesa in corso, con una riga da confermare a mano.

## Cosa è reale e cosa è demo

| Parte | Stato |
| --- | --- |
| Database, API, autenticazione (utente anonimo + JWT) | Reale |
| Ottimizzatore A/B, promo con carta fedeltà, 3x2, sostituzione generici | Reale |
| Pipeline scontrini: parsing, matching per alias/trigram, controllo totale, anti-duplicato, limite giornaliero, crediti, serie | Reale |
| Rilevamento anomalie (mediana + MAD) e consenso tra utenti per i prezzi da scontrino | Reale |
| OCR | **Demo** di default. `OCR_PROVIDER=google_vision` + `GOOGLE_VISION_API_KEY` in `docker-compose.yml` per leggere le foto vere |
| Negozi e prezzi | **Demo** (generati). Gli scraper dei portali e dei volantini non sono inclusi: vanno scritti catena per catena, dopo la verifica legale |
| Abbonamento Premium | **Demo** (attivazione gratuita con `DEV_MODE=1`). In produzione: acquisti in-app (es. RevenueCat) |
| Geocodifica CAP | Nominatim (OpenStreetMap), adatto ai test; in produzione meglio una tabella CAP nel backend |
| Mappe | Tile OpenStreetMap, adatte ai test; in produzione serve un provider con licenza per l'uso commerciale |

## Configurazione del backend

| Variabile | Default | Significato |
| --- | --- | --- |
| `DATABASE_URL` | `postgresql://postgres@localhost:5432/smartpantry` | Connessione PostgreSQL (con PostGIS) |
| `JWT_SECRET` | valore di sviluppo | **Cambialo** in produzione |
| `DEV_MODE` | `1` | Abilita Premium demo e `/v1/dev/seed-near`. Metti `0` in produzione |
| `OCR_PROVIDER` | `demo` | `demo` oppure `google_vision` |
| `GOOGLE_VISION_API_KEY` | vuoto | Chiave per Cloud Vision |
| `PRICE_MAX_AGE_DAYS` | `21` | Prezzi più vecchi non vengono usati |

## Prossimi passi verso la produzione

- Scraper livello 1 (portali online) e livello 2 (volantini) come worker separati che scrivono in `price_observations`, previa verifica legale catena per catena.
- Job periodico del price resolver (oggi gira alla conferma di ogni scontrino).
- Login vero (Apple/Google/email) collegato all'utente anonimo; acquisti in-app per Premium.
- Scansione del codice a barre in lista (`mobile_scanner`) usando l'endpoint esistente `/v1/products/by-ean/{ean}`.
