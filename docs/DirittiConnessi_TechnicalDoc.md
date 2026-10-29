# Documentazione Tecnica — Motore Diritti Connessi SCF

**Progetto:** SIAE — NTT Data  
**Ultimo aggiornamento:** 2026-05-01  
**Classi documentate:**
- `SIAE_POSH_PricingMdAPlan`
- `SIAE_UTIL_DirittiConnessiEngine`
- `SIAE_UTIL_DirittiConnessiRuleEngine`
- `SIAE_DTO_DirittiConnessiResult`

---

## 1. Architettura generale

Il motore calcola i diritti connessi SCF per ogni riga d'ordine (OrderItem) durante il processo di pricing di Salesforce Revenue Cloud. Il flusso è:

```
Revenue Cloud (Signaling)
        │
        ▼
SIAE_POSH_PricingMdAPlan          ← Post-hook, punto di ingresso
        │  queryTags / updateContextAttributes
        │
        ├─► SIAE_UTIL_CalculateCommercialQuote   (calcolo MdA / accordo commerciale)
        │
        ├─► [classifyAcconciatori / classifyAffittiBrevi]   (pre-classificazione per licenze speciali)
        │
        ├─► SIAE_UTIL_DirittiConnessiEngine       (orchestratore DC)
        │         │
        │         └─► SIAE_UTIL_DirittiConnessiRuleEngine   (valutazione regole)
        │
        └─► updateContextAttributes              (scrittura risultati nel contesto)
```

Il risultato del motore DC (`SIAE_DTO_DirittiConnessiResult`) viene usato per:
- Scrivere `SIAE_DirittiConnessi__c` sul nodo di contesto
- Sommare il subtotale DC al `NetTotalPrice` dell'item

---

## 2. Oggetti di configurazione

Prima di configurare le regole è necessario che esistano i record nei tre oggetti seguenti, nell'ordine indicato.

---

### 2.1 `SIAE_DirittiConnessiConfig__mdt` — Configurazione per licenza

**Tipo:** Custom Metadata  
**Scopo:** Abilita il calcolo DC per un determinato prodotto Salesforce e associa il prodotto a un set di regole e tariffe.

| Campo API | Tipo | Obbligatorio | Descrizione |
|---|---|---|---|
| `DeveloperName` | Text | ✓ | Identificatore univoco della config. Deve corrispondere al valore di `SIAE_LicenseConfig__c` nelle regole e al valore di `SIAE_ConfigName__c` nelle tariffe. |
| `SIAE_ProductCode__c` | Text | ✓ | `ProductCode` del `Product2` in Salesforce a cui si applica questa config. |
| `SIAE_CalculationEnabled__c` | Checkbox | ✓ | Se `false`, il calcolo DC è disabilitato per questo prodotto anche se esistono regole. |

**Esempio:**
```
DeveloperName         = Acconciatori
SIAE_ProductCode__c   = SIAE-PROD-ACCONCIATORI
SIAE_CalculationEnabled__c = true
```

---

### 2.2 `SIAE_DirittiConnessiTariffa__c` — Tabella tariffe a scaglioni

**Tipo:** Custom Object  
**Scopo:** Contiene gli importi tariffari per ogni tipo di dispositivo, suddivisi per scaglioni del valore di riferimento (superficie, camere, soci, ecc.).

| Campo API | Tipo | Obbligatorio | Descrizione |
|---|---|---|---|
| `SIAE_ConfigName__c` | Text | ✓ | Deve corrispondere al `DeveloperName` della Config__mdt. |
| `SIAE_DeviceType__c` | Text | ✓ | Tipo di dispositivo (es. `Radio`, `TV`, `AltroAudio`). Deve corrispondere al `SIAE_DeviceType__c` delle regole. |
| `SIAE_BracketFrom__c` | Number | ✓ | Inizio scaglione (incluso). |
| `SIAE_BracketTo__c` | Number | ✓ | Fine scaglione (incluso). Usare `999999` per "illimitato". |
| `SIAE_Amount__c` | Currency | ✓ | Importo base per lo scaglione. |
| `SIAE_ExtraAmountPerUnit__c` | Currency | | Importo aggiuntivo flat per ogni unità oltre lo scaglione massimo. |
| `SIAE_ExtraPercentage__c` | Number | | Percentuale aggiuntiva per ogni unità oltre lo scaglione massimo (alternativa a flat). |
| `SIAE_ExtraUnitSize__c` | Number | | Dimensione dell'unità per il calcolo dell'extra (es. ogni 100mq). Default: 1. |

**Logica scaglioni oltre il massimo:**  
Se il valore di riferimento supera tutti gli scaglioni, l'engine prende l'ultimo scaglione e calcola:
- Con `ExtraAmountPerUnit__c`: `Amount + (⌈surplus / ExtraUnitSize⌉ × ExtraAmount)`
- Con `ExtraPercentage__c`: `Amount × (1 + ExtraPercentage × ⌈surplus / ExtraUnitSize⌉)`

**Esempio (Bar e Ristoranti, Radio):**
```
ConfigName    = Bar_Ristoranti
DeviceType    = Radio
BracketFrom   = 0,     BracketTo = 75,     Amount = 17.03
BracketFrom   = 76,    BracketTo = 250,    Amount = 23.12
BracketFrom   = 251,   BracketTo = 500,    Amount = 57.14,  ExtraPercentage = 0.10,  ExtraUnitSize = 100
```

---

### 2.3 `SIAE_DirittiConnessiRule__c` — Regole di calcolo

**Tipo:** Custom Object  
**Scopo:** Definisce le regole di calcolo per ogni licenza. Ogni record rappresenta una riga di calcolo che viene valutata in sequenza. Le regole scattano tutte quelle la cui condizione è vera (non si escludono a vicenda, salvo che la condizione non le discrimini).

| Campo API | Tipo | Obbligatorio | Descrizione |
|---|---|---|---|
| `SIAE_LicenseConfig__c` | Text | ✓ | Deve corrispondere al `DeveloperName` della Config__mdt. |
| `SIAE_Order__c` | Number | ✓ | Ordine di esecuzione ASC. **Critico** per le regole che usano `SCONTO_SUL_TOTALE_PCT`. |
| `SIAE_Attribute__c` | Text | | Codice attributo OrderItem su cui valutare la condizione. |
| `SIAE_Operator__c` | Picklist | ✓ | Operatore della condizione. Vedi tabella operatori sotto. |
| `SIAE_ValueFrom__c` | Text | | Valore di confronto (inizio range per `BETWEEN`, lista per `IN`). |
| `SIAE_ValueTo__c` | Text | | Fine range (solo per `BETWEEN`). |
| `SIAE_DeviceType__c` | Text | ✓ | Tipo dispositivo usato per il lookup della tariffa in `SIAE_DirittiConnessiTariffa__c`. |
| `SIAE_Action__c` | Picklist | ✓ | Tipo di calcolo da applicare. Vedi tabella azioni sotto. |
| `SIAE_ActionValue__c` | Number | | Valore numerico dell'azione (percentuale, importo flat, moltiplicatore). |
| `SIAE_ApplyFromUnit__c` | Number | | Unità dalla quale inizia ad applicarsi la regola (default: 1). |
| `SIAE_ApplyToUnit__c` | Number | | Unità fino alla quale si applica la regola (default: quantità totale). |
| `SIAE_AttributeTreshold__c` | Text | | Codice attributo da usare come valore scaglione per il lookup CMT. Se blank, usa `SIAE_Attribute__c`. |
| `SIAE_AttributeQuantity__c` | Text | | Codice attributo da cui leggere la quantità di dispositivi. |
| `SIAE_AttributeQuantityList__c` | Text | | Lista di codici attributo separati da `;` da **sommare** per ottenere la quantità totale (es. `SIAE-ATTR-RADIO;SIAE-ATTR-AUDIO`). Ha precedenza su `SIAE_AttributeQuantity__c`. |
| `SIAE_Note__c` | Text | | Nota descrittiva per il configuratore. Non usata dall'engine. |

---

#### Operatori (`SIAE_Operator__c`)

| Valore | Descrizione | Campi utilizzati |
|---|---|---|
| `ALWAYS` | La regola scatta sempre, senza condizione. | — |
| `EQ` | Uguaglianza. Funziona sia su stringhe (case-insensitive) che su numeri. | `SIAE_Attribute__c`, `SIAE_ValueFrom__c` |
| `IN` | Il valore dell'attributo è contenuto in una lista. Separare i valori con `,` in `ValueFrom`. | `SIAE_Attribute__c`, `SIAE_ValueFrom__c` |
| `LTE` | Minore o uguale (numerico). | `SIAE_Attribute__c`, `SIAE_ValueFrom__c` |
| `GT` | Maggiore stretto (numerico). | `SIAE_Attribute__c`, `SIAE_ValueFrom__c` |
| `BETWEEN` | Compreso tra due valori (numerico, estremi inclusi). | `SIAE_Attribute__c`, `SIAE_ValueFrom__c`, `SIAE_ValueTo__c` |
| `EQ_TOTAL` | Somma dei valori degli attributi in `SIAE_AttributeQuantityList__c` uguale a `ValueFrom`. | `SIAE_AttributeQuantityList__c`, `SIAE_ValueFrom__c` |

---

#### Azioni (`SIAE_Action__c`)

| Valore | Formula | Descrizione |
|---|---|---|
| `TARIFFA_BASE` | `tariffa × unità` | Importo base da CMT per le unità presenti. |
| `MAGGIORAZIONE_PCT` | `(tariffa × ActionValue%) × unità` | Aggiunge una percentuale della tariffa base per ogni unità. |
| `MAGGIORAZIONE_FLAT` | `ActionValue × unità` | Aggiunge un importo fisso per ogni unità. |
| `RIDUZIONE_PCT` | `tariffa × ((100 - ActionValue) / 100) × unità` | Restituisce la tariffa ridotta della percentuale. **Usare per sconti su singola unità** (es. 2a e 3a radio nei Circoli). |
| `RIDUZIONE_FLAT` | `-(ActionValue × unità)` | Sottrae un importo fisso per ogni unità. |
| `MOLTIPLICATORE` | `tariffa × (ActionValue - 1) × unità` | Aggiunge l'importo extra per un moltiplicatore (es. TV >40" che vale il doppio: ActionValue = 2). |
| `SCONTO_SUL_TOTALE_PCT` | `-(totaleRigheAccumulato × ActionValue%)` | Applica uno sconto percentuale sul **subtotale già calcolato** dalle regole precedenti. **Usare per riduzioni sul totale** (es. -40% solo radio in luogo comune). La regola deve avere un ordine di esecuzione superiore alle regole base. |

---

#### Meccanismo `ApplyFromUnit` / `ApplyToUnit`

Questi campi permettono di applicare la regola solo a un sottoinsieme delle unità presenti.

**Esempio:** 3 radio, regola con `ApplyFrom=3` → si applica solo alla 3a radio (1 unità).  
**Esempio:** 5 radio, regola con `ApplyFrom=2`, `ApplyTo=2` → si applica solo alla 2a radio (1 unità).

La quantità totale viene determinata da `SIAE_AttributeQuantityList__c` (se presente) o da `SIAE_AttributeQuantity__c`. Se nessuno dei due è valorizzato, la quantità è sempre 1.

---

## 3. Classi Apex

---

### 3.1 `SIAE_POSH_PricingMdAPlan`

**Tipo:** Global class, implementa `RevSignaling.SignalingApexProcessor`  
**Ruolo:** Post-hook invocato da Revenue Cloud al momento del calcolo del prezzo. È il punto di ingresso dell'intera catena di calcolo.

**Responsabilità:**
1. Interroga il contesto Revenue Cloud per ottenere i nodi `SalesTransactionItem` e `SalesTransactionItemAttribute`
2. Parsa i nodi in strutture tipizzate (`SalesTransactionItemNode`)
3. Calcola il compenso MdA tramite `SIAE_UTIL_CalculateCommercialQuote`
4. Per licenze con classificazione speciale (Acconciatori, Affitti brevi), inietta un attributo virtuale `SIAE-ATTR-FASCIA-TARIFFA` prima del calcolo DC
5. Chiama `SIAE_UTIL_DirittiConnessiEngine` per il calcolo DC
6. Rimuove l'attributo virtuale dopo il calcolo DC
7. Somma il risultato DC al `NetTotalPrice` e scrive tutti i valori aggiornati nel contesto

**Inner classes principali:**

| Classe | Descrizione |
|---|---|
| `SalesTransactionItemNode` | Rappresenta un nodo `SalesTransactionItem` del contesto. Contiene `attributeValueByCode` (mappa codice→valore di tutti gli attributi), `attributeToUpdate` (mappa degli aggiornamenti da inviare al contesto), `paymentWrapper` (voci di pagamento). |
| `SalesTransactionItemAttributeNode` | Rappresenta un nodo `SalesTransactionItemAttribute`. Figlio di `SalesTransactionItemNode`. |
| `PaymentWrapper` / `PaymentItem` | Struttura JSON per `SIAE_PaymentItems__c`. |

**Metodi di classificazione speciale:**

- `classifyAcconciatori(attributeValueByCode)` — Determina la colonna tariffaria per la licenza Acconciatori in base ai dispositivi presenti (`SIAE-ATTR-RADIO`, `SIAE-ATTR-TV-UND40`, `SIAE-ATTR-TV-OVR40`, `SIAE-ATTR-AUDIO`, `SIAE-ATTR-CLASS`, `SIAE-ATTR-QTA`). Restituisce: `FasciaA`, `Store`, `RadioPiuTV`, `RadioOTV`, `AltroApp`, o `null`.
- `classifyAffittiBrevi(attributeValueByCode, config)` — Determina la fascia tariffaria per Affitti brevi in base al totale dispositivi e al numero di camere. Restituisce: `1 Stella` o `2 Stelle`.

Il valore restituito da questi metodi viene inserito come attributo virtuale `SIAE-ATTR-FASCIA-TARIFFA` nella mappa `attributeValueByCode` del nodo **solo per la durata del calcolo DC**, e rimosso subito dopo. Le regole DC di queste licenze usano `SIAE-ATTR-FASCIA-TARIFFA` come attributo di condizione.

---

### 3.2 `SIAE_UTIL_DirittiConnessiEngine`

**Tipo:** Public class, stateless  
**Ruolo:** Orchestratore del calcolo DC. Carica la configurazione da org e chiama il motore regole per ogni item.

**Metodo principale:** `calculate(listOfSalesItemNode, setOfProductCode, mapProductIdProduct)`

**Flusso interno:**
1. Carica i record `SIAE_DirittiConnessiConfig__mdt` per i ProductCode presenti negli item
2. Per ogni config abilitata, carica tariffe (`SIAE_DirittiConnessiTariffa__c`) e regole (`SIAE_DirittiConnessiRule__c`) raggruppate per `LicenseConfig`
3. Per ogni item, risolve la config corrispondente e chiama `SIAE_UTIL_DirittiConnessiRuleEngine.evaluate()`
4. Aggrega i risultati nel DTO di ritorno

**Nota:** Se un item non ha un `ProductCode` corrispondente a una Config abilitata, viene semplicemente saltato senza errori.

---

### 3.3 `SIAE_UTIL_DirittiConnessiRuleEngine`

**Tipo:** Public class, stateless  
**Ruolo:** Motore di valutazione delle regole. Per ogni item valuta sequenzialmente tutte le regole della licenza e calcola l'importo riga per riga.

**Metodo principale:** `evaluate(itemNode, attributi, regole, tariffe, config)`

**Flusso per ogni regola:**
1. `conditionMatches()` — verifica se la condizione della regola è soddisfatta
2. `getTresholdValue()` — legge il valore scaglione (es. mq, soci) per il lookup CMT
3. `getRate()` — cerca la tariffa in `SIAE_DirittiConnessiTariffa__c` per `DeviceType` + valore scaglione
4. `getQuantity()` — calcola le unità totali (da attributo singolo o somma di lista)
5. Calcola le unità effettive nel range `[ApplyFrom, ApplyTo]`
6. `calculateLineItemPrice()` — applica l'azione e restituisce l'importo riga
7. Applica `periodicityCoefficient` e `discountDc` dell'item all'importo
8. Accumula in `totaleRighe`

**Coefficienti applicati a ogni riga:**
- `periodicityCoefficient` — coefficiente di stagionalità/periodicità (letto dal tag `SIAE_CoeffStagionalita__c` del contesto). Se `null` o 0, l'importo diventa 0.
- `discountDc` — sconto percentuale DC (espresso come decimale, es. `0.20` = 20%). Applicato come `(1 - discountDc)`.

**Formula finale per ogni riga:**
```
importoRiga = calculateLineItemPrice(...)
importoRiga = (importoRiga × periodicityCoefficient) × (1 - discountDc)
```

---

### 3.4 `SIAE_DTO_DirittiConnessiResult`

**Tipo:** Public DTO class  
**Ruolo:** Struttura dati di ritorno del motore DC.

**Struttura:**
```
SIAE_DTO_DirittiConnessiResult
├── totaleComplessivo: Decimal          // Somma dei subtotali di tutti gli item
└── dettagliPerOrderItem: List<LicenzaDetail>
        └── LicenzaDetail
            ├── orderItemId: String     // lineItemId dell'item (ID nodo contesto)
            ├── subtotale: Decimal      // Totale DC per questo item (arrotondato a 2 decimali)
            ├── importoVoceIncassoPrimaria: Decimal
            ├── importoVoceIncassoSecondaria: Decimal
            └── dettagliDispositivi: List<DispositivoDetail>
                    └── DispositivoDetail
                        ├── tipoDispositivo: String    // DeviceType della regola
                        ├── unitaApplicata: Integer    // Unità su cui è stata applicata la regola
                        ├── importoBase: Decimal       // Tariffa CMT usata
                        ├── importoModifica: Decimal   // importoRiga + (tariffa × unità)
                        ├── importoRiga: Decimal       // Importo netto della riga
                        └── nota: String
```

---

## 4. Guida rapida alla configurazione di una nuova licenza

### Step 1 — Creare il record `SIAE_DirittiConnessiConfig__mdt`
- `DeveloperName` = nome univoco della licenza (es. `NuovaLicenza`)
- `SIAE_ProductCode__c` = ProductCode del prodotto in org
- `SIAE_CalculationEnabled__c` = `true`

### Step 2 — Inserire le tariffe in `SIAE_DirittiConnessiTariffa__c`
Per ogni tipo di dispositivo e per ogni scaglione del valore di riferimento:
- `SIAE_ConfigName__c` = `DeveloperName` della config
- `SIAE_DeviceType__c` = stringa libera (es. `Radio`, `TV`) — deve corrispondere a quello usato nelle regole
- `SIAE_BracketFrom__c` / `SIAE_BracketTo__c` = range dello scaglione
- `SIAE_Amount__c` = importo

### Step 3 — Inserire le regole in `SIAE_DirittiConnessiRule__c`
Ordinare le regole per `SIAE_Order__c`. Schema tipico:

```
Ordine 10:  TARIFFA_BASE     → calcola l'importo base
Ordine 20:  MAGGIORAZIONE_PCT → aggiunge % per dispositivi extra
Ordine 30:  MAGGIORAZIONE_FLAT → aggiunge importo fisso per altri dispositivi
Ordine 90:  SCONTO_SUL_TOTALE_PCT → applica sconto finale sul totale (se presente)
```

### Step 4 — Verificare il calcolo
Usare uno script Apex anonimo o un log del contesto per verificare che le regole producano i valori attesi. I debug di `SIAE_POSH_PricingMdAPlan` loggano sia il contesto raw che il risultato DC.

---

## 5. Licenze con classificazione speciale (attributo virtuale)

Alcune licenze richiedono che la scelta della colonna tariffaria venga calcolata automaticamente prima del calcolo DC, perché dipende da combinazioni di più attributi che l'engine non può valutare con una singola condizione.

Per queste licenze, `SIAE_POSH_PricingMdAPlan` inietta un attributo virtuale `SIAE-ATTR-FASCIA-TARIFFA` nella mappa degli attributi dell'item **prima** di chiamare l'engine DC, e lo rimuove **subito dopo**. Le regole DC di queste licenze usano `SIAE-ATTR-FASCIA-TARIFFA` come attributo di condizione con operatore `EQ` o `IN`.

| Licenza | ProductCode | Metodo di classificazione | Valori possibili |
|---|---|---|---|
| Acconciatori | `SIAE-PROD-ACCONCIATORI` | `classifyAcconciatori()` | `FasciaA`, `RadioOTV`, `RadioPiuTV`, `AltroApp`, `Store` |
| Affitti brevi | `SIAE-PROD-AFFITTI-BREVI` | `classifyAffittiBrevi()` | `1 Stella`, `2 Stelle` |

Per aggiungere una nuova licenza con classificazione speciale, aggiungere un branch nel loop di pre-classificazione in `SIAE_POSH_PricingMdAPlan.executeInternal()` (righe 123-140) e implementare il metodo `@TestVisible private static String classifyXxx(...)`.
