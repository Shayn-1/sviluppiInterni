/**
 * @description Utility statiche per il PreHook SIAE.
 *              Contiene tutti i calcoli di fascia e coefficiente
 *              che il PreHook deve eseguire prima della Pricing Procedure.
 *
 * @author      Domenico Del Prete
 * @group       NTT Data - SIAE
 */
public class SIAE_UTIL_PricingMdA {

    private static final String DEBUG_VERSION = 'SIAE_POST_Pricing_V1';

    // =========================================================================
    // FLAT AUDIO / VIDEO - COSTANTI
    // =========================================================================

    private static final String FIELD_FLAT_AUDIO = 'SIAE_FlatAudio__c';
    private static final String FIELD_FLAT_VIDEO = 'SIAE_FlatVideo__c';

    private static final String FIELD_FLAT_AUDIO_SEMESTRALE = 'SIAE_FlatAudioSemestrale__c';
    private static final String FIELD_FLAT_AUDIO_TRIMESTRALE = 'SIAE_FlatAudioTrimestrale__c';
    private static final String FIELD_FLAT_VIDEO_SEMESTRALE = 'SIAE_FlatVideoSemestrale__c';
    private static final String FIELD_FLAT_VIDEO_TRIMESTRALE = 'SIAE_FlatVideoTrimestrale__c';

    private static final String CONF_FIELD_USA_FLAT = 'SIAE_UsaFlat__c';
    private static final String CONF_FIELD_AGGIUNGI_A_FLAT = 'SIAE_AggiungiAFLAT__c';
    private static final String CONF_FIELD_ESCLUDI_FLAT_AUDIO = 'SIAE_EscludiFlatAudio__c';
    private static final String CONF_FIELD_COEFF_SEMESTRALE = 'SIAE_CoeffStag_Semestrale__c';
    private static final String CONF_FIELD_COEFF_TRIMESTRALE = 'SIAE_CoeffStag_Trimestrale__c';

    private static final Integer MIN_MESI_SEMESTRALE = 6;
    private static final Integer MIN_MESI_TRIMESTRALE = 3;

    // =========================================================================
    // DIFFERENZIAZIONE ALTOPARLANTI / MONITOR
    // =========================================================================

    public static final String FIELD_DIFF_ALTOPARLANTI = 'SIAE_DiffAltoparlanti__c';
    public static final String FIELD_DIFF_MONITOR      = 'SIAE_DiffMonitor__c';

    private static final String VALUE_ALTOPARLANTE = 'Altoparlante';
    private static final String VALUE_MONITOR      = 'Monitor';

    // =========================================================================
    // DEFAULT TypeOfCoverage
    // =========================================================================

    public static String defaultTypeCoverage(String currentValue, SIAE_ConfigurazionePricing__c conf) {
        return !String.isBlank(currentValue)
            ? currentValue
            : conf == null || conf.SIAE_UsaDefaultTypeCoverage__c != true || String.isBlank(conf.SIAE_DefaultTypeCoverageValue__c)
                ? 'Annuale'
                : conf.SIAE_DefaultTypeCoverageValue__c;
    }

    // =========================================================================
    // STAGIONALITA
    // =========================================================================

    public static Decimal coeffStagionalita(String typeCoverage, SIAE_ConfigurazionePricing__c conf) {
        return coeffStagionalita(typeCoverage, conf, null);
    }

    public static Decimal coeffStagionalita(String typeCoverage, SIAE_ConfigurazionePricing__c conf, Date effectiveDate) {
        if (conf == null) return 1.0;

        String normalizedCoverage = String.isBlank(typeCoverage) ? 'Annuale' : typeCoverage.trim();
        Decimal coefficiente;
        switch on normalizedCoverage {
            when 'Annuale'{
                coefficiente = conf.SIAE_CoeffStag_Annuale__c;
                if (effectiveDate != null) {
                Integer mesiResidui = 13 - effectiveDate.month();

                Decimal coeffAnnuale = coefficiente != null ? coefficiente : 1.0;

                return coeffAnnuale * (Decimal.valueOf(mesiResidui) / 12);
                }
            }
            when 'Semestrale' {
                coefficiente = conf.SIAE_CoeffStag_Semestrale__c;
            }
            when 'Trimestrale' {
                coefficiente = conf.SIAE_CoeffStag_Trimestrale__c;
            }
            when 'Mensile' {
                coefficiente = conf.SIAE_CoeffStag_Mensile__c;
            }
            when else {
                coefficiente = 1.0;
            }
        }
        return coefficiente != null ? coefficiente : 1.0;
    }

    // =========================================================================
    // MAGGIORAZIONE AREE ESTERNE
    // =========================================================================

    public static Decimal fattoreMaggiorazioneEsterna(String mqAreeEsterne, SIAE_ConfigurazionePricing__c conf) {
        if (conf == null || conf.SIAE_UsaMaggiorazioneEsterna__c != true || String.isBlank(mqAreeEsterne) || mqAreeEsterne == 'No') return 1.0;

        Decimal valFino50 = conf.SIAE_AreeEsterne_ValoreFino50__c;
        Decimal valOltre50 = conf.SIAE_AreeEsterne_ValoreOltre50__c;

        return mqAreeEsterne == 'Si, fino a 50 mq' ? valFino50 : valOltre50;
    }

    // =========================================================================
    // FATTORE MQ OLTRE 500
    // =========================================================================

    public static Decimal fattoreMQOltre500(Decimal mq, SIAE_ConfigurazionePricing__c conf) {
        if (conf == null || conf.SIAE_UsaMaggiorazioneMQ__c != true) return 1.0;

        Decimal sogliaBase = conf.SIAE_MQ_SogliaBase__c;
        Decimal tranche = conf.SIAE_MQ_Tranche__c;
        Decimal incremento = conf.SIAE_MQ_IncrementoPerTranche__c;
        Decimal coeffBase = conf.SIAE_MQ_CoeffBase__c;

        return mq == null || mq <= sogliaBase
            ? 1.0
            : coeffBase + (Decimal.valueOf((Integer)Math.ceil((mq - sogliaBase) / tranche)) * incremento);
    }

    // =========================================================================
    // ENTE PUBBLICO (Condizione Speciale)
    // =========================================================================

    public static final String ATTR_COND_SPE = 'SIAE-ATTR-COND-SPE';
    public static final String COND_SPE_SI    = 'SI';

    /**
     * True se l'attributo Condizione Speciale (SIAE-ATTR-COND-SPE) indica un
     * ente pubblico / ambiente aperto al pubblico (valore 'SI').
     */
    public static Boolean isEntePubblico(String condSpeValue) {
        return COND_SPE_SI.equalsIgnoreCase(condSpeValue);
    }

    /**
     * Per gli enti pubblici (COND-SPE = SI) la licenza e' sempre trattata come
     * fascia 26-50 dipendenti (gestita dalla decision table Calcolo Tariffe
     * Dispositivi): non si applica quindi la maggiorazione oltre 200 dipendenti.
     * Azzera i tre importi in-place; no-op negli altri casi.
     */
    public static void azzeraMaggiorazioneDipSeEntePubblico(Map<String, Decimal> importiDip, String condSpeValue) {
        if (importiDip != null && isEntePubblico(condSpeValue)) {
            importiDip.put('radio', 0);
            importiDip.put('audio', 0);
            importiDip.put('video', 0);
        }
    }

    // =========================================================================
    // DIPENDENTI OLTRE 200
    // =========================================================================

    public static Map<String, Decimal> importoDipendentiOltre200(Integer numDipendenti, SIAE_ConfigurazionePricing__c conf) {
        Map<String, Decimal> risultati = new Map<String, Decimal>{
            'radio' => 0,
            'audio' => 0,
            'video' => 0
        };

        if (conf == null || conf.SIAE_UsaMaggiorazioneDipendenti__c != true) {
            return risultati;
        }

        Integer sogliaBase = Integer.valueOf(conf.SIAE_Dip_SogliaBase__c);
        Integer tranche = Integer.valueOf(conf.SIAE_Dip_Tranche__c);

        Decimal impRadio = conf.SIAE_Dip_ImportoRadio__c;
        Decimal impAudio = conf.SIAE_Dip_ImportoAudio__c;
        Decimal impVideo = conf.SIAE_Dip_ImportoVideo__c;

        if (numDipendenti == null || numDipendenti <= sogliaBase) {
            return risultati;
        }

        Integer scatti = (Integer)Math.ceil((numDipendenti - sogliaBase) / Decimal.valueOf(tranche));

        risultati.put('radio', Decimal.valueOf(scatti) * impRadio);
        risultati.put('audio', Decimal.valueOf(scatti) * impAudio);
        risultati.put('video', Decimal.valueOf(scatti) * impVideo);

        return risultati;
    }

    // =========================================================================
    // TV > 40"
    // =========================================================================

    public static Decimal fattoreTV40(SIAE_ConfigurazionePricing__c conf) {
        return conf == null || conf.SIAE_UsaMaggiorazioneTV40__c != true
            ? 1.0
            : conf.SIAE_TV40_Coefficiente__c;
    }

    // =========================================================================
    // DIFFERENZIAZIONE ALTOPARLANTI / MONITOR
    // =========================================================================

    /**
     * Se la configurazione del prodotto ha SIAE_DifferenziaAltoparlanti__c attivo,
     * questi due valori vengono scritti sull'item (SIAE_DiffAltoparlanti__c /
     * SIAE_DiffMonitor__c) e usati dal pricing engine per scegliere il binario di
     * tier corretto sul Price Adjustment Schedule "Calcolo Tariffa Altoparlanti SIAE",
     * che altrimenti ha fasce Altoparlante/Monitor sovrapposte per lo stesso prodotto
     * e fallisce con OVERLAPPING_ADJUSTMENT_TIERS.
     */
    public static String altoparlanteValue(SIAE_ConfigurazionePricing__c conf) {
        return isDifferenziaAltoparlantiAttiva(conf) ? VALUE_ALTOPARLANTE : null;
    }

    public static String monitorValue(SIAE_ConfigurazionePricing__c conf) {
        return isDifferenziaAltoparlantiAttiva(conf) ? VALUE_MONITOR : null;
    }

    private static Boolean isDifferenziaAltoparlantiAttiva(SIAE_ConfigurazionePricing__c conf) {
        return conf != null && conf.SIAE_DifferenziaAltoparlanti__c == true;
    }

    // =========================================================================
    // RISOLUZIONE ATTRIBUTI PICKLIST (Id -> Value testuale)
    // =========================================================================

    /**
     * Risolve in bulk gli Id di AttributePicklistValue nel loro Value testuale.
     * Gli attributi di tipo Picklist espongono nel context/JSON di pricing solo
     * l'Id del valore selezionato (tag/chiave AttributePicklistValue) e non il
     * testo (tag/chiave AttributeValue), che arriva quindi vuoto se non risolto.
     */
    public static Map<Id, String> resolvePicklistValues(Set<Id> picklistValueIds) {
        Map<Id, String> picklistValueById = new Map<Id, String>();

        if (picklistValueIds == null || picklistValueIds.isEmpty()) {
            return picklistValueById;
        }

        for (AttributePicklistValue picklistValue : [
            SELECT Id, Value
            FROM AttributePicklistValue
            WHERE Id IN :picklistValueIds
        ]) {
            picklistValueById.put(picklistValue.Id, picklistValue.Value);
        }

        return picklistValueById;
    }

    /**
     * Risolve in bulk, per una lista di nodi SalesTransactionItemAttribute in
     * formato JSON piatto (chiavi AttributeDefinitionCode/AttributeValue/
     * AttributePicklistValue, come usato dal PreHook/PostHook Flow), gli
     * eventuali valori Picklist esposti solo come Id: il testo risolto viene
     * scritto direttamente sulla chiave AttributeValue di ciascun nodo, in place.
     */
    public static void resolvePicklistAttributeValues(List<Object> attrList) {
        if (attrList == null || attrList.isEmpty()) {
            return;
        }

        Set<Id> picklistValueIds = new Set<Id>();
        for (Object attrObj : attrList) {
            if (!(attrObj instanceof Map<String, Object>)) { continue; }
            Map<String, Object> attr = (Map<String, Object>) attrObj;
            String attrVal = (String) attr.get('AttributeValue');
            String picklistId = (String) attr.get('AttributePicklistValue');

            if (String.isBlank(attrVal) && String.isNotBlank(picklistId)) {
                try {
                    picklistValueIds.add((Id) picklistId);
                } catch (Exception e) {
                    System.debug(DEBUG_VERSION + ' - Picklist value Id non valido: ' + picklistId);
                }
            }
        }

        if (picklistValueIds.isEmpty()) {
            return;
        }

        Map<Id, String> picklistValueById = resolvePicklistValues(picklistValueIds);

        for (Object attrObj : attrList) {
            if (!(attrObj instanceof Map<String, Object>)) { continue; }
            Map<String, Object> attr = (Map<String, Object>) attrObj;
            String attrVal = (String) attr.get('AttributeValue');
            String picklistId = (String) attr.get('AttributePicklistValue');

            if (String.isNotBlank(attrVal) || String.isBlank(picklistId)) { continue; }

            try {
                String resolvedValue = picklistValueById.get((Id) picklistId);
                if (String.isNotBlank(resolvedValue)) {
                    attr.put('AttributeValue', resolvedValue);
                }
            } catch (Exception e) {
                // Id già validato nel primo passaggio: nessuna azione necessaria
            }
        }
    }

    // =========================================================================
    // HELPER: parse sicuro di Decimal e Integer da String
    // =========================================================================

    public static Decimal parseDecimal(String val) {
        if (String.isBlank(val)) {
            return null;
        }

        try {
            return Decimal.valueOf(val.trim().replace(',', '.'));
        } catch (Exception e) {
            return null;
        }
    }

    public static Integer parseInteger(String val) {
        Decimal d = parseDecimal(val);
        return d != null ? Integer.valueOf(d) : null;
    }

    /**
     * Calcola i mesi interi residui dalla startDate fino al 31/12 dell'anno corrente.
     * Restituisce 0 se la data è nulla/non parsabile.
     */
    public static Integer calcMesiResidui(String startDateStr) {
        if (String.isBlank(startDateStr)) return 0;

        try {
            return calcMesiResidui(Date.valueOf(startDateStr));
        } catch (Exception e) {
            System.debug(DEBUG_VERSION + ' - startDate non parsabile: ' + startDateStr);
            return 0;
        }
    }

    public static Integer calcMesiResidui(Date startDt) {
        return startDt == null ? 0 : 13 - startDt.month();
    }

    public static Decimal applyAnnualProRata(Decimal originalValue, Integer mesiResidui, SIAE_ConfigurazionePricing__c conf) {
        if (originalValue == null || mesiResidui == null) {
            return originalValue;
        }

        Decimal coeffAnnuale = (conf != null && conf.SIAE_CoeffStag_Annuale__c != null)
            ? conf.SIAE_CoeffStag_Annuale__c
            : 1.0;

        Decimal proRata = originalValue * coeffAnnuale * (Decimal.valueOf(mesiResidui) / 12);
        return roundMoney(proRata);
    }

    public static void applyAnnualProRata(Map<String, Object> item, String fieldName, Integer mesiResidui, SIAE_ConfigurazionePricing__c conf) {
        if (item == null || String.isBlank(fieldName) || !item.containsKey(fieldName) || item.get(fieldName) == null) {
            return;
        }

        Decimal originalValue = toDecimal(item.get(fieldName));

        if (originalValue == null) {
            System.debug(DEBUG_VERSION + ' - Impossibile applicare pro-rata su ' + fieldName + ': valore non numerico.');
            return;
        }

        item.put(fieldName, applyAnnualProRata(originalValue, mesiResidui, conf));
    }

    /**
     * Moltiplica il valore del campo per il coefficiente fornito.
     */
    public static void applyCoeff(Map<String, Object> item, String fieldName, Decimal coeff) {
        if (item == null || String.isBlank(fieldName) || coeff == null) {
            return;
        }

        if (!item.containsKey(fieldName) || item.get(fieldName) == null) {
            return;
        }

        Decimal originalValue = toDecimal(item.get(fieldName));

        if (originalValue == null) {
            System.debug(DEBUG_VERSION + ' - Impossibile applicare coefficiente su ' + fieldName + ': valore non numerico.');
            return;
        }

        item.put(fieldName, roundMoney(originalValue * coeff));
    }

    // =========================================================================
    // FLAT AUDIO / VIDEO - BASE + STAGIONALI + DISPOSITIVI EXTRA A-FLAT
    // =========================================================================

    /**
     * Metodo principale da usare nella posthook.
     *
     * sourceItem = item originale del context, contenente anche gli attributi
     *              e i relativi SIAE_DeviceTotalPrice.
     *
     * targetItem = item filtrato su cui scrivere i campi finali.
     *
     * coeffAreeEsterne = maggiorazione SIAE-ATTR-AREE-EST (1.0 se non applicabile),
     *                     applicata alla base flat audio/video prima di sommare
     *                     i dispositivi aggiuntivi A-FLAT.
     */
    public static void applyFlatAmounts(
        Map<String, Object> sourceItem,
        Map<String, Object> targetItem,
        SIAE_ConfigurazionePricing__c conf,
        Integer mesiResidui,
        Decimal coeffAreeEsterne
    ) {
        if (targetItem == null) {
            return;
        }

        Map<String, Object> calculationContext = buildFlatCalculationContext(sourceItem, targetItem);
        Map<String, Decimal> flatAmounts = calculateFlatAmounts(calculationContext, conf, mesiResidui, coeffAreeEsterne);

        for (String fieldName : flatAmounts.keySet()) {
            targetItem.put(fieldName, flatAmounts.get(fieldName));
        }
    }

    /**
     * Overload utile per altre classi quando source e target coincidono.
     */
    public static void applyFlatAmounts(
        Map<String, Object> item,
        SIAE_ConfigurazionePricing__c conf,
        Integer mesiResidui,
        Decimal coeffAreeEsterne
    ) {
        applyFlatAmounts(item, item, conf, mesiResidui, coeffAreeEsterne);
    }

    /**
     * Overload utile quando la classe chiamante ha solo la startDate.
     */
    public static void applyFlatAmounts(
        Map<String, Object> sourceItem,
        Map<String, Object> targetItem,
        SIAE_ConfigurazionePricing__c conf,
        String startDateStr,
        Decimal coeffAreeEsterne
    ) {
        applyFlatAmounts(sourceItem, targetItem, conf, calcMesiResidui(startDateStr), coeffAreeEsterne);
    }

    /**
     * Calcola tutti i valori flat:
     * - SIAE_FlatAudio__c / SIAE_FlatVideo__c con eventuali dispositivi extra A-FLAT;
     * - SIAE_FlatAudioSemestrale__c / Trimestrale;
     * - SIAE_FlatVideoSemestrale__c / Trimestrale.
     *
     * Se il context contiene almeno un attributo configurato in SIAE_EscludiFlatAudio__c
     * con valore > 0, tutta la famiglia flat audio viene azzerata.
     *
     * coeffAreeEsterne = maggiorazione SIAE-ATTR-AREE-EST (1.0 se non applicabile),
     *                     applicata alla base flat audio/video (SIAE_FlatAudio__c /
     *                     SIAE_FlatVideo__c) prima di sommare i dispositivi aggiuntivi
     *                     A-FLAT, che restano esclusi dalla maggiorazione.
     *
     * Il metodo non muta direttamente la mappa di input.
     */
    public static Map<String, Decimal> calculateFlatAmounts(
        Map<String, Object> sourceItem,
        SIAE_ConfigurazionePricing__c conf,
        Integer mesiResidui,
        Decimal coeffAreeEsterne
    ) {
        Map<String, Decimal> result = initializeFlatAmountsResult();

        if (sourceItem == null || !isFlatEnabled(conf)) {
            return result;
        }

        Decimal safeCoeffAreeEsterne = coeffOrOne(coeffAreeEsterne);
        Decimal additionalFlatAmount = calculateAdditionalFlatAmount(sourceItem, conf);

        Decimal flatAudioBase = readDecimal(sourceItem, FIELD_FLAT_AUDIO);
        Decimal flatVideoBase = readDecimal(sourceItem, FIELD_FLAT_VIDEO);

        Decimal flatAudioBaseWithMaggiorazione = (flatAudioBase == null ? 0 : flatAudioBase) * safeCoeffAreeEsterne;
        Decimal flatVideoBaseWithMaggiorazione = (flatVideoBase == null ? 0 : flatVideoBase) * safeCoeffAreeEsterne;

        Boolean excludeFlatAudio = hasExcludedFlatAudioAttributes(sourceItem, conf);

        Decimal flatAudioFinal = excludeFlatAudio
            ? 0
            : calculateBaseFlatAmount(flatAudioBaseWithMaggiorazione, additionalFlatAmount);

        Decimal flatVideoFinal = calculateBaseFlatAmount(flatVideoBaseWithMaggiorazione, additionalFlatAmount);

        result.put(FIELD_FLAT_AUDIO, flatAudioFinal);
        result.put(FIELD_FLAT_VIDEO, flatVideoFinal);

        Decimal coeffSemestrale = readConfigDecimal(conf, CONF_FIELD_COEFF_SEMESTRALE);
        Decimal coeffTrimestrale = readConfigDecimal(conf, CONF_FIELD_COEFF_TRIMESTRALE);

        result.put(
            FIELD_FLAT_AUDIO_SEMESTRALE,
            excludeFlatAudio
                ? 0
                : calculateSeasonalFlatAmount(flatAudioFinal, coeffSemestrale, mesiResidui, MIN_MESI_SEMESTRALE)
        );

        result.put(
            FIELD_FLAT_AUDIO_TRIMESTRALE,
            excludeFlatAudio
                ? 0
                : calculateSeasonalFlatAmount(flatAudioFinal, coeffTrimestrale, mesiResidui, MIN_MESI_TRIMESTRALE)
        );

        result.put(
            FIELD_FLAT_VIDEO_SEMESTRALE,
            calculateSeasonalFlatAmount(flatVideoFinal, coeffSemestrale, mesiResidui, MIN_MESI_SEMESTRALE)
        );

        result.put(
            FIELD_FLAT_VIDEO_TRIMESTRALE,
            calculateSeasonalFlatAmount(flatVideoFinal, coeffTrimestrale, mesiResidui, MIN_MESI_TRIMESTRALE)
        );

        return result;
    }

    /**
     * Overload utile quando la classe chiamante ha solo la startDate.
     */
    public static Map<String, Decimal> calculateFlatAmounts(
        Map<String, Object> sourceItem,
        SIAE_ConfigurazionePricing__c conf,
        String startDateStr,
        Decimal coeffAreeEsterne
    ) {
        return calculateFlatAmounts(sourceItem, conf, calcMesiResidui(startDateStr), coeffAreeEsterne);
    }

    /**
     * Verifica se nel context è presente almeno uno degli attributi configurati
     * in SIAE_AggiungiAFLAT__c con valore > 0.
     */
    public static Boolean hasAdditionalFlatAttributes(
        Map<String, Object> sourceItem,
        SIAE_ConfigurazionePricing__c conf
    ) {
        return !getAdditionalFlatAttributeNodes(sourceItem, conf).isEmpty();
    }

    /**
     * Verifica se nel context è presente almeno uno degli attributi configurati
     * in SIAE_EscludiFlatAudio__c con valore > 0.
     *
     * Se true, il metodo calculateFlatAmounts azzera:
     * - SIAE_FlatAudio__c
     * - SIAE_FlatAudioSemestrale__c
     * - SIAE_FlatAudioTrimestrale__c
     */
    public static Boolean hasExcludedFlatAudioAttributes(
        Map<String, Object> sourceItem,
        SIAE_ConfigurazionePricing__c conf
    ) {
        if (sourceItem == null || conf == null) {
            return false;
        }

        Set<String> attributeCodesToExclude = getExcludedFlatAudioAttributeCodes(conf);

        if (attributeCodesToExclude.isEmpty()) {
            return false;
        }

        for (Map<String, Object> attributeNode : getAttributeNodes(sourceItem)) {
            String attributeCode = normalizeAttributeCode(getAttributeCode(attributeNode));

            if (String.isBlank(attributeCode) || !attributeCodesToExclude.contains(attributeCode)) {
                continue;
            }

            Decimal attributeValue = getAttributeValue(attributeNode);

            if (attributeValue != null && attributeValue > 0) {
                return true;
            }
        }

        return false;
    }

    /**
     * Somma il SIAE_DeviceTotalPrice degli attributi configurati in
     * SIAE_AggiungiAFLAT__c, solo se il valore dell'attributo è > 0.
     *
     * Esempio configurazione:
     * SIAE-ATTR-JUKEBOX;SIAE-ATTR-VIDEO-JUKEBOX;SIAE-ATTR-KARAOKE
     */
    public static Decimal calculateAdditionalFlatAmount(
        Map<String, Object> sourceItem,
        SIAE_ConfigurazionePricing__c conf
    ) {
        if (sourceItem == null || conf == null) {
            return 0;
        }

        Decimal total = 0;

        for (Map<String, Object> attributeNode : getAdditionalFlatAttributeNodes(sourceItem, conf)) {
            Decimal deviceTotalPrice = getDeviceTotalPrice(attributeNode);

            if (deviceTotalPrice != null && deviceTotalPrice > 0) {
                total += deviceTotalPrice;
            }
        }

        return roundMoney(total);
    }

    /**
     * Restituisce i nodi attributo configurati in SIAE_AggiungiAFLAT__c
     * e valorizzati con valore > 0 nel context.
     */
    public static List<Map<String, Object>> getAdditionalFlatAttributeNodes(
        Map<String, Object> sourceItem,
        SIAE_ConfigurazionePricing__c conf
    ) {
        List<Map<String, Object>> result = new List<Map<String, Object>>();

        if (sourceItem == null || conf == null) {
            return result;
        }

        Set<String> attributeCodesToAdd = getAdditionalFlatAttributeCodes(conf);

        if (attributeCodesToAdd.isEmpty()) {
            return result;
        }

        for (Map<String, Object> attributeNode : getAttributeNodes(sourceItem)) {
            String attributeCode = normalizeAttributeCode(getAttributeCode(attributeNode));

            if (String.isBlank(attributeCode) || !attributeCodesToAdd.contains(attributeCode)) {
                continue;
            }

            Decimal attributeValue = getAttributeValue(attributeNode);

            if (attributeValue != null && attributeValue > 0) {
                result.add(attributeNode);
            }
        }

        return result;
    }

    /**
     * Restituisce i codici AttributeDefinition configurati in SIAE_AggiungiAFLAT__c.
     */
    public static Set<String> getAdditionalFlatAttributeCodes(SIAE_ConfigurazionePricing__c conf) {
        Set<String> result = new Set<String>();

        if (conf == null) {
            return result;
        }

        String rawValue = readConfigString(conf, CONF_FIELD_AGGIUNGI_A_FLAT);

        if (String.isBlank(rawValue)) {
            return result;
        }

        for (String token : rawValue.split(';')) {
            String normalizedCode = normalizeAttributeCode(token);

            if (String.isNotBlank(normalizedCode)) {
                result.add(normalizedCode);
            }
        }

        return result;
    }

    /**
     * Restituisce i codici AttributeDefinition configurati in SIAE_EscludiFlatAudio__c.
     *
     * Esempio configurazione:
     * SIAE-ATTR-RADIO;SIAE-ATTR-AUDIO
     */
    public static Set<String> getExcludedFlatAudioAttributeCodes(SIAE_ConfigurazionePricing__c conf) {
        Set<String> result = new Set<String>();

        if (conf == null) {
            return result;
        }

        String rawValue = readConfigString(conf, CONF_FIELD_ESCLUDI_FLAT_AUDIO);

        if (String.isBlank(rawValue)) {
            return result;
        }

        for (String token : rawValue.split(';')) {
            String normalizedCode = normalizeAttributeCode(token);

            if (String.isNotBlank(normalizedCode)) {
                result.add(normalizedCode);
            }
        }

        return result;
    }

    /**
     * Lettura sicura di un Decimal da una mappa context.
     */
    public static Decimal readDecimal(Map<String, Object> sourceItem, String fieldName) {
        if (sourceItem == null || String.isBlank(fieldName) || !sourceItem.containsKey(fieldName)) {
            return null;
        }

        return toDecimal(sourceItem.get(fieldName));
    }

    // =========================================================================
    // FLAT RATE - TOTAL DA
    // =========================================================================

    /**
     * Calcola il valore da scrivere in SIAE_TotalDA__c per le flat Bar/Ristoranti.
     *
     * La logica si attiva solo se SIAE_TypeOfFlatRate__c è valorizzato.
     *
     * Formula flat:
     * baseAmount * coeffMaggiorazioneMQ * coeffAreeEsterne * coeffStagionalita
     *
     * Se SIAE_TypeOfFlatRate__c non è valorizzato, restituisce semplicemente
     * il baseAmount arrotondato.
     */
    public static Decimal calculateTotalDAForFlatRate(
        Decimal baseAmount,
        String typeOfFlatRate,
        Decimal coeffMaggiorazioneMQ,
        Decimal coeffAreeEsterne,
        Decimal coeffStagionalita
    ) {
        Decimal safeBaseAmount = baseAmount == null ? 0 : baseAmount;

        if (!isFlatRateSelected(typeOfFlatRate)) {
            return roundMoney(safeBaseAmount);
        }

        Decimal totalDA =
            safeBaseAmount *
            coeffOrOne(coeffMaggiorazioneMQ) *
            coeffOrOne(coeffAreeEsterne) *
            coeffOrOne(coeffStagionalita);

        return roundMoney(totalDA);
    }

    /**
     * Verifica se è stata scelta una flat.
     *
     * Valori attesi:
     * - FLAT AUDIO
     * - FLAT AUDIO-VIDEO
     *
     * Per ora basta la valorizzazione del campo, perché il campo viene popolato
     * solo quando la flat è effettivamente selezionata.
     */
    public static Boolean isFlatRateSelected(String typeOfFlatRate) {
        return String.isNotBlank(typeOfFlatRate);
    }

    private static Decimal coeffOrOne(Decimal coeff) {
        return coeff == null ? 1 : coeff;
    }

    // =========================================================================
    // FLAT AUDIO / VIDEO - HELPER PRIVATI
    // =========================================================================

    private static Map<String, Object> buildFlatCalculationContext(
        Map<String, Object> sourceItem,
        Map<String, Object> targetItem
    ) {
        Map<String, Object> result = new Map<String, Object>();

        if (targetItem != null) {
            result.putAll(targetItem);
        }

        if (sourceItem != null) {
            result.putAll(sourceItem);
        }

        return result;
    }

    private static Map<String, Decimal> initializeFlatAmountsResult() {
        Map<String, Decimal> result = new Map<String, Decimal>();

        result.put(FIELD_FLAT_AUDIO, 0);
        result.put(FIELD_FLAT_VIDEO, 0);
        result.put(FIELD_FLAT_AUDIO_SEMESTRALE, 0);
        result.put(FIELD_FLAT_AUDIO_TRIMESTRALE, 0);
        result.put(FIELD_FLAT_VIDEO_SEMESTRALE, 0);
        result.put(FIELD_FLAT_VIDEO_TRIMESTRALE, 0);

        return result;
    }

    private static Decimal calculateBaseFlatAmount(Decimal baseValue, Decimal additionalFlatAmount) {
        return roundMoney((baseValue == null ? 0 : baseValue) + (additionalFlatAmount == null ? 0 : additionalFlatAmount));
    }

    private static Decimal calculateSeasonalFlatAmount(
        Decimal baseValue,
        Decimal coeff,
        Integer mesiResidui,
        Integer minMesiResidui
    ) {
        if (baseValue == null || coeff == null || mesiResidui == null || mesiResidui < minMesiResidui) {
            return 0;
        }

        return roundMoney(baseValue * coeff);
    }

    private static Boolean isFlatEnabled(SIAE_ConfigurazionePricing__c conf) {
        Object rawValue = safeGetConfigValue(conf, CONF_FIELD_USA_FLAT);

        if (rawValue == null) {
            return false;
        }

        if (rawValue instanceof Boolean) {
            return (Boolean) rawValue;
        }

        return String.valueOf(rawValue).equalsIgnoreCase('true');
    }

    private static List<Map<String, Object>> getAttributeNodes(Map<String, Object> sourceItem) {
        List<Map<String, Object>> result = new List<Map<String, Object>>();

        if (sourceItem == null) {
            return result;
        }

        Object rawAttributes = null;

        if (sourceItem.containsKey('SalesTransactionItemAttribute')) {
            rawAttributes = sourceItem.get('SalesTransactionItemAttribute');
        } else if (sourceItem.containsKey('SalesTransactionItemAttributes')) {
            rawAttributes = sourceItem.get('SalesTransactionItemAttributes');
        } else if (sourceItem.containsKey('attributes')) {
            rawAttributes = sourceItem.get('attributes');
        } else if (sourceItem.containsKey('Attributes')) {
            rawAttributes = sourceItem.get('Attributes');
        }

        if (rawAttributes == null) {
            return result;
        }

        if (rawAttributes instanceof List<Object>) {
            for (Object rawNode : (List<Object>) rawAttributes) {
                if (rawNode instanceof Map<String, Object>) {
                    result.add((Map<String, Object>) rawNode);
                }
            }
        } else if (rawAttributes instanceof Map<String, Object>) {
            result.add((Map<String, Object>) rawAttributes);
        }

        return result;
    }

    private static String getAttributeCode(Map<String, Object> attributeNode) {
        if (attributeNode == null) {
            return null;
        }

        Object rawCode = firstNotNull(attributeNode, new List<String>{
            'AttributeDefinitionCode',
            'attributeCode',
            'AttributeCode',
            'SIAE_AttributeCode__c',
            'Code',
            'code'
        });

        return rawCode == null ? null : String.valueOf(rawCode);
    }

    private static Decimal getAttributeValue(Map<String, Object> attributeNode) {
        if (attributeNode == null) {
            return null;
        }

        Object rawValue = firstNotNull(attributeNode, new List<String>{
            'AttributeValue',
            'attributeValue',
            'Value',
            'value',
            'SIAE_AttributeValue__c'
        });

        return toDecimal(rawValue);
    }

    private static Decimal getDeviceTotalPrice(Map<String, Object> attributeNode) {
        if (attributeNode == null) {
            return null;
        }

        Object rawValue = firstNotNull(attributeNode, new List<String>{
            'SIAE_DeviceTotalPrice',
            'SIAE_DeviceTotalPrice__c',
            'deviceTotalPrice',
            'DeviceTotalPrice'
        });

        return toDecimal(rawValue);
    }

    private static Object firstNotNull(Map<String, Object> source, List<String> keys) {
        if (source == null || keys == null) {
            return null;
        }

        for (String key : keys) {
            if (String.isBlank(key)) {
                continue;
            }

            if (source.containsKey(key) && source.get(key) != null) {
                return source.get(key);
            }
        }

        return null;
    }

    private static String normalizeAttributeCode(String attributeCode) {
        return String.isBlank(attributeCode) ? null : attributeCode.trim().toUpperCase();
    }

    private static Decimal readConfigDecimal(SIAE_ConfigurazionePricing__c conf, String fieldApiName) {
        return toDecimal(safeGetConfigValue(conf, fieldApiName));
    }

    private static String readConfigString(SIAE_ConfigurazionePricing__c conf, String fieldApiName) {
        Object rawValue = safeGetConfigValue(conf, fieldApiName);
        return rawValue == null ? null : String.valueOf(rawValue);
    }

    private static Object safeGetConfigValue(SIAE_ConfigurazionePricing__c conf, String fieldApiName) {
        if (conf == null || String.isBlank(fieldApiName)) {
            return null;
        }

        try {
            return conf.get(fieldApiName);
        } catch (Exception e) {
            System.debug(DEBUG_VERSION + ' - Campo configurazione non leggibile ' + fieldApiName + ': ' + e.getMessage());
            return null;
        }
    }

    private static Decimal toDecimal(Object rawValue) {
        if (rawValue == null) {
            return null;
        }

        String valueAsString = String.valueOf(rawValue);

        if (String.isBlank(valueAsString)) {
            return null;
        }

        valueAsString = valueAsString.trim().replace(',', '.');

        try {
            return Decimal.valueOf(valueAsString);
        } catch (Exception e) {
            return null;
        }
    }

    private static Decimal roundMoney(Decimal value) {
        return value == null ? 0 : value.setScale(2, RoundingMode.HALF_UP);
    }
}