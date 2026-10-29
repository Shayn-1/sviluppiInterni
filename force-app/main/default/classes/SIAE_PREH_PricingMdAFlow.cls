/**
 * @description       : Classe Apex invocabile da AutoLaunched Flow.
 * Riceve un JSON (jsonDataString) con la struttura SalesTransaction,
 * applica la logica di calcolo di SIAE e restituisce il JSON arricchito.
 *
 * @author            : Gaetano Iuliano
 * @group             : NTT Data - SIAE
 * @last modified on  : 07-28-2026
**/
public class SIAE_PREH_PricingMdAFlow {

    private static final String DEBUG_VERSION = 'SIAE_PREH_PricingMdAFlow';
    private static final String ATTR_QTA      = 'SIAE-ATTR-QTA';
    private static final String ATTR_AREE_EST = 'SIAE-ATTR-AREE-EST';

    private static final String TYPE_OF_COVERAGE     = 'SIAE_TypeOfCoverage__c';
    private static final String FIELD_COEFF_MAGG_MQ  = 'SIAE_CoeffMaggiorazioneMQ__c';
    private static final String FIELD_COEFF_AREE_EST = 'SIAE_CoeffAreeEsterne__c';
    private static final String FIELD_COEFF_STAG     = 'SIAE_CoeffStagionalita__c';
    private static final String FIELD_COEFF_TV40     = 'SIAE_CoeffMaggiorazioneTV40__c';
    private static final String FIELD_MAGG_DIP_RADIO = 'SIAE_CoeffMaggiorazioneDipendentiRadio__c';
    private static final String FIELD_MAGG_DIP_AUDIO = 'SIAE_CoeffMaggiorazioneDipendentiAudio__c';
    private static final String FIELD_MAGG_DIP_VIDEO = 'SIAE_CoeffMaggiorazioneDipendentiVideo__c';

    private static final String ATTR_LUOGO            = 'SIAE-ATTR-LUOGO';
    private static final String FIELD_DIVIDI_COMP_VAL = 'SIAE_DividiCompensoValore__c';
    
    private static final String ATTR_LICENZA_RISTORAZIONE = 'SIAE-ATTR-LIC-RIST';
    private static final String FIELD_LICENZA_RIST = 'SIAE_LicenzaRistorazione__c';
    
    private static final String ATTR_NUOVA_STRUTTURA = 'SIAE-ATTR-NUOVA-STRU';
    private static final String FIELD_NUOVA_STRU = 'SIAE_NuovaStruttura__c';

    public class FlowInput {
        @InvocableVariable(
            label       = 'JSON SalesTransaction (input)'
            description = 'JSON string con struttura SalesTransaction da elaborare'
            required    = true
        )
        public String jsonDataString;
    }

    public class FlowOutput {
        @InvocableVariable(
            label       = 'JSON SalesTransaction arricchito (output)'
            description = 'JSON originale con i campi calcolati aggiunti su ogni SalesTransactionItem'
        )
        public String enrichedJsonString;

        @InvocableVariable(
            label       = 'Esito elaborazione'
            description = 'SUCCESS oppure ERROR'
        )
        public String status;

        @InvocableVariable(
            label       = 'Messaggio di dettaglio'
            description = 'Descrizione del risultato o dell errore riscontrato'
        )
        public String message;
    }

    @InvocableMethod(
        label       = 'SIAE - Pricing Pre-Hook (JSON)'
        description = 'Calcola i coefficienti di pricing SIAE su un JSON SalesTransaction e restituisce il JSON arricchito'
        category    = 'SIAE Pricing'
    )
    public static List<FlowOutput> execute(List<FlowInput> inputs) {
        List<FlowOutput> outputs = new List<FlowOutput>();
        for (FlowInput inp : inputs) {
            outputs.add(processJson(inp.jsonDataString));
        }
        return outputs;
    }

    private static FlowOutput processJson(String jsonDataString) {
        FlowOutput output = new FlowOutput();

        try {
            System.debug(DEBUG_VERSION + ' - START');

            if (String.isBlank(jsonDataString)) {
                output.status             = 'ERROR';
                output.message            = DEBUG_VERSION + ': jsonDataString è nullo o vuoto.';
                output.enrichedJsonString = jsonDataString;
                return output;
            }

            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(jsonDataString);

            // Lettura del JSON tramite il layer RCA (righe DELETED escluse, picklist risolte)
            RCASalesTransaction salesTransaction = RCAJsonReader.read(root, null);

            if (salesTransaction.transactions.isEmpty()) {
                output.status             = 'SUCCESS';
                output.message            = DEBUG_VERSION + ': nessuna SalesTransaction trovata nel JSON.';
                output.enrichedJsonString = jsonDataString;
                return output;
            }

            // ─── STEP 1: Raccogli i Product2 Id dai SalesTransactionItem ───────────────
            Set<Id> productIds = new Set<Id>();

            for (RCASalesTransaction.ItemNode item : salesTransaction.items) {
                String productIdStr = item.productId;

                if (String.isNotBlank(productIdStr)) {
                    try {
                        productIds.add((Id)productIdStr);
                    } catch (Exception e) {
                        System.debug(DEBUG_VERSION + ' - Product Id non valido nel JSON: ' + productIdStr);
                    }
                }
            }

            // ─── STEP 2: Carica indice configurazioni per Product2 ───────────────────
            MdAPricingConfiguration.ConfigurationIndex pricingConfigurations =
                MdAPricingConfiguration.load(productIds);

            // ─── STEP 3: Calcoli ed arricchimento JSON ─────────────────────────────────
            Integer totalItemsProcessed = 0;

            for (RCASalesTransaction.ItemNode item : salesTransaction.items) {
                // Recupero Configurazione Prodotto
                String productIdStr = item.productId;
                SIAE_ConfigurazionePricing__c conf = null;
                if (String.isNotBlank(productIdStr)) {
                    try {
                        conf = pricingConfigurations.resolve(
                            (Id)productIdStr,
                            RCAValueConverter.asDate(item.effectiveFrom)
                        );
                    } catch(Exception e) {}
                }

                // Il valore picklist risolto viene riscritto su AttributeValue del nodo attributo
                for (RCASalesTransaction.AttributeNode attribute : item.attributes) {
                    if (attribute.resolvedFromPicklist) {
                        attribute.attributeToUpdate.put('AttributeValue', attribute.attributeValue);
                    }
                }

                Map<String, String> attrValues = item.attributeValueByCode;

                String  qtaValue          = attrValues.get(ATTR_QTA);
                Decimal mq                = SIAE_UTIL_PricingMdA.parseDecimal(qtaValue);

                // Se la configurazione manca, applichiamo valori safe/default e NON generiamo ERROR
                Boolean hasConf = (conf != null);

                Decimal coeffMaggMQ       = hasConf ? SIAE_UTIL_PricingMdA.fattoreMQOltre500(mq, conf) : 0;
                String  areeEstValue      = attrValues.get(ATTR_AREE_EST);
                Decimal coeffAreeEsterne  = hasConf ? SIAE_UTIL_PricingMdA.fattoreMaggiorazioneEsterna(areeEstValue, conf) : 1;

                String  currentTOC        = item.typeCoverage;
                String  normalizedTOC     = hasConf ? SIAE_UTIL_PricingMdA.defaultTypeCoverage(currentTOC, conf) : currentTOC;
                Decimal coeffStagionalita = hasConf ? SIAE_UTIL_PricingMdA.coeffStagionalita(normalizedTOC, conf, null) : 1;

                Decimal coeffTV40         = hasConf ? SIAE_UTIL_PricingMdA.fattoreTV40(conf) : 1;

                Integer numDipendenti     = SIAE_UTIL_PricingMdA.parseInteger(qtaValue);
                Map<String, Decimal> importiDip = hasConf ? SIAE_UTIL_PricingMdA.importoDipendentiOltre200(numDipendenti, conf) : null;

                // Ente pubblico (COND-SPE=SI): sempre fascia 26-50, nessuna
                // maggiorazione oltre 200 dipendenti.
                String  condSpeValue      = attrValues.get(SIAE_UTIL_PricingMdA.ATTR_COND_SPE);
                SIAE_UTIL_PricingMdA.azzeraMaggiorazioneDipSeEntePubblico(importiDip, condSpeValue);

                Decimal importoDipRadio   = (importiDip != null && importiDip.containsKey('radio')) ? importiDip.get('radio') : 0;
                Decimal importoDipAudio   = (importiDip != null && importiDip.containsKey('audio')) ? importiDip.get('audio') : 0; 
                Decimal importoDipVideo   = (importiDip != null && importiDip.containsKey('video')) ? importiDip.get('video') : 0; 

                // Dividi Compenso
                String luogoValue = attrValues.get(ATTR_LUOGO);
                Decimal dividiCompenso = 1;
                if (hasConf) {
                    dividiCompenso = (luogoValue != null && luogoValue == 'Solo a terra' && conf.SIAE_DividiCompensoValore__c != null)
                        ? conf.SIAE_DividiCompensoValore__c
                        : 1;
                }
                
                // Licenza Ristorazione
                String licRis = attrValues.get(ATTR_LICENZA_RISTORAZIONE);
                Decimal licenzaRist = 1;
                if (hasConf) {
                    licenzaRist = (licRis != null && licRis == 'SI') ? 1 : conf.SIAE_LicenzaRistorazione_Valore__c;
                }

                // Nuova Struttura
                String nuoStru = attrValues.get(ATTR_NUOVA_STRUTTURA);
                Decimal nuovaStru = 1;
                if (hasConf) {
                    nuovaStru = (nuoStru != null && nuoStru == 'SI') ? conf.SIAE_NuovaStruttura_Valore__c : 1;
                }

                item.attributeToUpdate.put(FIELD_COEFF_MAGG_MQ,  coeffMaggMQ);
                item.attributeToUpdate.put(FIELD_COEFF_AREE_EST, coeffAreeEsterne);
                item.attributeToUpdate.put(FIELD_COEFF_STAG,     coeffStagionalita);
                item.attributeToUpdate.put(TYPE_OF_COVERAGE,     normalizedTOC);
                item.attributeToUpdate.put(FIELD_COEFF_TV40,     coeffTV40);
                item.attributeToUpdate.put(FIELD_MAGG_DIP_RADIO, importoDipRadio);
                item.attributeToUpdate.put(FIELD_MAGG_DIP_AUDIO, importoDipAudio);
                item.attributeToUpdate.put(FIELD_MAGG_DIP_VIDEO, importoDipVideo);
                item.attributeToUpdate.put(FIELD_DIVIDI_COMP_VAL, dividiCompenso);
                item.attributeToUpdate.put(FIELD_LICENZA_RIST,   licenzaRist);
                item.attributeToUpdate.put(FIELD_NUOVA_STRU,     nuovaStru);
                item.attributeToUpdate.put(SIAE_UTIL_PricingMdA.FIELD_DIFF_ALTOPARLANTI, SIAE_UTIL_PricingMdA.altoparlanteValue(conf));
                item.attributeToUpdate.put(SIAE_UTIL_PricingMdA.FIELD_DIFF_MONITOR,      SIAE_UTIL_PricingMdA.monitorValue(conf));

                totalItemsProcessed++;
            }

            RCAJsonWriter.apply(root, salesTransaction);

            output.enrichedJsonString = JSON.serialize(root);
            output.status             = 'SUCCESS';
            output.message            = DEBUG_VERSION + ': completato con ' + totalItemsProcessed + ' item elaborati.';

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, DEBUG_VERSION + ' - ERRORE riga ' + e.getLineNumber() + ': ' + e.getMessage() + ' | ' + e.getStackTraceString());
            output.status             = 'ERROR';
            output.message            = DEBUG_VERSION + ' Errore riga ' + e.getLineNumber() + ': ' + e.getMessage();
            output.enrichedJsonString = jsonDataString; 
        }

        return output;
    }
}