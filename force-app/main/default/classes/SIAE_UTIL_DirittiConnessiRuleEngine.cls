/**
 * @description       :
 * @author            : Domenico Del Prete - domenico.delprete@nttdata.com
 * @group             : NTT Data
 * @last modified on  : 04-28-2026
 * @last modified by  : Domenico Del Prete - domenico.delprete@nttdata.com
 **/
public with sharing class SIAE_UTIL_DirittiConnessiRuleEngine {

    // Coperture con un proprio coefficiente di stagionalità DC sulla tariffa:
    // Annuale -> SIAE_CoeffStagionalitaDC__c, Semestrale -> _Semestrale__c,
    // Trimestrale -> _Trimestrale__c. Copertura non valorizzata vale Annuale
    // per default; Mensile non è gestita dalla stagionalità DC.
    private static final String COVERAGE_ANNUALE     = 'Annuale';
    private static final String COVERAGE_SEMESTRALE  = 'Semestrale';
    private static final String COVERAGE_TRIMESTRALE = 'Trimestrale';

    /*// ─── Lookup tariffa CMT ───────────────────────────────────────────────────

    @TestVisible
    private static Decimal getTariffa(
        Map<String, DirittiConnessi_Tariffa__mdt> idx,
        String configName,
        String tipoDispositivo,
        Decimal valoreScaglione,
        List<DirittiConnessi_Tariffa__mdt> tariffe
    ) {
        if (String.isBlank(tipoDispositivo) || valoreScaglione == null) return 0;

        // Cerca la tariffa il cui scaglione contiene il valore, con il più alto Scaglione_A che ancora lo contiene
        DirittiConnessi_Tariffa__mdt migliore = null;
        Decimal importoExtra = 0;
        Decimal scaglioneMaxA = 0;

        for (DirittiConnessi_Tariffa__mdt t : tariffe) {
            if (t.Config_Name__c != configName) continue;
            if (t.Tipo_Dispositivo__c != tipoDispositivo) continue;

            Decimal da = (t.Scaglione_Da__c != null) ? t.Scaglione_Da__c : 0;
            Decimal a  = (t.Scaglione_A__c  != null) ? t.Scaglione_A__c  : 999999;

            if (valoreScaglione >= da && valoreScaglione <= a) {
                migliore = t;
                break;
            }

            // Tracciamo lo scaglione massimo per calcolare l'extra oltre soglia
            if (a > scaglioneMaxA) {
                scaglioneMaxA = a;
            }
        }

        if (migliore != null) {
            return migliore.Importo__c != null ? migliore.Importo__c : 0;
        }

        // Valore oltre tutti gli scaglioni: prendi l'ultimo e aggiungi extra
        DirittiConnessi_Tariffa__mdt ultimo = getUltimoScaglione(tariffe, configName, tipoDispositivo);
        if (ultimo == null) return 0;

        Decimal base = ultimo.Importo__c != null ? ultimo.Importo__c : 0;
        if (ultimo.Importo_Extra_Per_Unita__c == null || ultimo.Importo_Extra_Per_Unita__c == 0) {
            return base;
        }

        Decimal grandezzaUnita = (ultimo.Grandezza_Unita_Extra__c != null && ultimo.Grandezza_Unita_Extra__c > 0)
            ? ultimo.Grandezza_Unita_Extra__c : 1;

        Decimal sogliaMassima = (ultimo.Scaglione_A__c != null) ? ultimo.Scaglione_A__c : 0;
        Decimal eccedenza = valoreScaglione - sogliaMassima;
        Decimal unitaExtra = Math.ceil(eccedenza / grandezzaUnita);
        return base + (unitaExtra * ultimo.Importo_Extra_Per_Unita__c);
    }*/

    /**
     * Valuta tutte le regole per un OrderItem e produce il dettaglio calcolo.
     */
    public static SIAE_DTO_DirittiConnessiResult.LicenzaDetail evaluate(
        RCASalesTransaction.ItemNode itemNode,
        Map<String, String> attributi,
        List<SIAE_DirittiConnessiRule__c> regole,
        List<SIAE_DirittiConnessiTariffa__c> tariffe,
        SIAE_DirittiConnessiConfig__mdt config
    ) {
        SIAE_DTO_DirittiConnessiResult.LicenzaDetail detail =
            new SIAE_DTO_DirittiConnessiResult.LicenzaDetail();

        if (itemNode == null) {
            return detail;
        }

        detail.orderItemId = itemNode.lineItemId;

        if (regole == null || regole.isEmpty()) {
            return detail;
        }

        if (tariffe == null) {
            tariffe = new List<SIAE_DirittiConnessiTariffa__c>();
        }

        Map<String, String> workingAttributi = attributi == null
            ? new Map<String, String>()
            : new Map<String, String>(attributi);

        if (config != null && config.DeveloperName == 'Acconciatori') {
            enrichAcconciatori(workingAttributi);
        }
        
        //FIX FLAT BAR
        enrichBarRistorantiFlatRateAttributes(
            itemNode,
            workingAttributi,
            config
        );

        Decimal totaleRighe = 0;

        Map<String, Integer> consumedUnitsByDeviceGroup = new Map<String, Integer>();

        for (SIAE_DirittiConnessiRule__c regola : regole) {
            if (regola == null) {
                continue;
            }
            
            //FIX FLAT BAR
            if (shouldSkipBarRistorantiRuleWhenFlatSelected(config, itemNode, regola)) {
                continue;
            }

            if (!conditionMatches(regola, workingAttributi)) {
                continue;
            }

            if (shouldSkipAcconciatoriStandaloneRadioTvRule(
                config,
                regola,
                workingAttributi
            )) {
                continue;
            }

            Decimal valoreScaglione = getTresholdValue(regola, workingAttributi);

            String valoreParametroSecondario = null;
            if (String.isNotBlank(regola.SIAE_SecondaryAttribute__c)) {
                valoreParametroSecondario = workingAttributi.get(regola.SIAE_SecondaryAttribute__c);
            }

            String configName = config == null ? null : config.DeveloperName;

            RateResolution rateResolution = resolveRate(
                configName,
                regola.SIAE_DeviceType__c,
                valoreScaglione,
                valoreParametroSecondario,
                tariffe
            );

            Decimal tariffa = rateResolution == null ? null : rateResolution.amount;

            if (tariffa == null) {
                continue;
            }

            Integer quantita = getQuantity(regola, workingAttributi);

            Integer unitaDaApplicare;

            if (String.isNotBlank(regola.SIAE_DeviceGroupKey__c)) {
                unitaDaApplicare = calculateUnitsToApplyWithDeviceGroup(
                    regola,
                    quantita,
                    consumedUnitsByDeviceGroup
                );
            } else {
                unitaDaApplicare = calculateUnitsToApplyStandard(
                    regola,
                    quantita
                );
            }

            if (unitaDaApplicare <= 0) {
                continue;
            }

            Decimal importoRiga = calculateLineItemPrice(
                regola,
                tariffa,
                unitaDaApplicare,
                valoreScaglione,
                configName,
                tariffe,
                totaleRighe
            );
            
            //FIX FLAT BAR
            importoRiga = applyBarRistorantiFlatMaggiorazioni(
                importoRiga,
                config,
                itemNode,
                regola
            );

            Decimal coeffStagionalita = resolveSeasonalityCoefficient(
                itemNode,
                rateResolution.tariffa
            );

            Decimal discountDc = itemNode.discountDc == null
                ? 0
                : itemNode.discountDc;

            Decimal importoRigaPreSconto = (importoRiga * coeffStagionalita)
                .setScale(2, RoundingMode.HALF_UP);

            importoRiga = ((importoRiga * coeffStagionalita) * (1 - discountDc))
                .setScale(2, RoundingMode.HALF_UP);

            detail.subtotalePreSconto += importoRigaPreSconto;

            SIAE_DTO_DirittiConnessiResult.DispositivoDetail dd =
                new SIAE_DTO_DirittiConnessiResult.DispositivoDetail();

            dd.tipoDispositivo = regola.SIAE_DeviceType__c;
            dd.revenueItem = regola.SIAE_RevenueItemDC__c;
            dd.revenueItemType = regola.SIAE_RevenueItemType__c;
            dd.instrumentId = regola.SIAE_IdInstrument__c;
            dd.unitaApplicata = unitaDaApplicare;
            dd.importoBase = tariffa;
            dd.importoModifica = importoRiga + (tariffa * unitaDaApplicare);
            dd.importoRiga = importoRiga;
            dd.nota = regola.SIAE_Note__c;

            detail.dettagliDispositivi.add(dd);

            totaleRighe += importoRiga;
        }

        detail.subtotale = totaleRighe.setScale(2, RoundingMode.HALF_UP);
        detail.subtotalePreSconto = detail.subtotalePreSconto.setScale(2, RoundingMode.HALF_UP);

        return detail;
    }

    @TestVisible
    private static Integer calculateUnitsToApplyStandard(
        SIAE_DirittiConnessiRule__c regola,
        Integer quantita
    ) {
        if (regola == null || quantita == null || quantita <= 0) {
            return 0;
        }

        Integer daUnita = regola.SIAE_ApplyFromUnit__c != null
            ? Integer.valueOf(regola.SIAE_ApplyFromUnit__c)
            : 1;

        Integer aUnita = regola.SIAE_ApplyToUnit__c != null
            ? Integer.valueOf(regola.SIAE_ApplyToUnit__c)
            : quantita;

        aUnita = Math.min(aUnita, quantita);

        if (daUnita > quantita) {
            return 0;
        }

        Integer unitaDaApplicare = aUnita - daUnita + 1;

        return unitaDaApplicare <= 0
            ? 0
            : unitaDaApplicare;
    }

    @TestVisible
    private static Integer calculateUnitsToApplyWithDeviceGroup(
        SIAE_DirittiConnessiRule__c regola,
        Integer quantita,
        Map<String, Integer> consumedUnitsByDeviceGroup
    ) {
        if (regola == null || quantita == null || quantita <= 0) {
            return 0;
        }

        if (String.isBlank(regola.SIAE_DeviceGroupKey__c)) {
            return calculateUnitsToApplyStandard(regola, quantita);
        }

        String deviceGroupKey = regola.SIAE_DeviceGroupKey__c.trim();

        Integer alreadyConsumed = consumedUnitsByDeviceGroup.containsKey(deviceGroupKey)
            ? consumedUnitsByDeviceGroup.get(deviceGroupKey)
            : 0;

        Integer applyFromUnit = regola.SIAE_ApplyFromUnit__c != null
            ? Integer.valueOf(regola.SIAE_ApplyFromUnit__c)
            : 1;

        Integer applyToUnit = regola.SIAE_ApplyToUnit__c != null
            ? Integer.valueOf(regola.SIAE_ApplyToUnit__c)
            : alreadyConsumed + quantita;

        Integer currentStart = alreadyConsumed + 1;
        Integer currentEnd = alreadyConsumed + quantita;

        Integer applicableStart = Math.max(currentStart, applyFromUnit);
        Integer applicableEnd = Math.min(currentEnd, applyToUnit);

        Integer unitsToApply = applicableEnd >= applicableStart
            ? applicableEnd - applicableStart + 1
            : 0;

        consumedUnitsByDeviceGroup.put(
            deviceGroupKey,
            alreadyConsumed + quantita
        );

        System.debug(
            LoggingLevel.WARN,
            'DC DeviceGroup -> group=' + deviceGroupKey +
            ', rule=' + regola.Name +
            ', quantity=' + quantita +
            ', alreadyConsumed=' + alreadyConsumed +
            ', applyFromUnit=' + applyFromUnit +
            ', applyToUnit=' + applyToUnit +
            ', currentStart=' + currentStart +
            ', currentEnd=' + currentEnd +
            ', unitsToApply=' + unitsToApply +
            ', newConsumed=' + consumedUnitsByDeviceGroup.get(deviceGroupKey)
        );

        return unitsToApply;
    }
    
    
    @TestVisible
    private static void enrichBarRistorantiFlatRateAttributes(
        RCASalesTransaction.ItemNode itemNode,
        Map<String, String> attrs,
        SIAE_DirittiConnessiConfig__mdt config
    ) {
        if (
            itemNode == null ||
            attrs == null ||
            !isBarRistorantiConfig(config) ||
            String.isBlank(itemNode.typeOfFlatRate)
        ) {
            return;
        }
    
        attrs.put('Num_FlatAudio', '0');
        attrs.put('Num_FlatAV', '0');
    
        if ('FLAT_AUDIO'.equalsIgnoreCase(itemNode.typeOfFlatRate)) {
            attrs.put('Num_FlatAudio', '1');
        } else if ('FLAT_AUDIO_VIDEO'.equalsIgnoreCase(itemNode.typeOfFlatRate)) {
            attrs.put('Num_FlatAV', '1');
        }
    
        System.debug(
            LoggingLevel.WARN,
            'DC Bar/Ristoranti flat selected -> typeOfFlatRate=' + itemNode.typeOfFlatRate +
            ', Num_FlatAudio=' + attrs.get('Num_FlatAudio') +
            ', Num_FlatAV=' + attrs.get('Num_FlatAV')
        );
    }
    
    @TestVisible
    private static Boolean shouldSkipBarRistorantiRuleWhenFlatSelected(
        SIAE_DirittiConnessiConfig__mdt config,
        RCASalesTransaction.ItemNode itemNode,
        SIAE_DirittiConnessiRule__c regola
    ) {
        if (
            !isBarRistorantiConfig(config) ||
            itemNode == null ||
            regola == null ||
            String.isBlank(itemNode.typeOfFlatRate)
        ) {
            return false;
        }
    
        String selectedFlat = itemNode.typeOfFlatRate.trim();
        String deviceType = regola.SIAE_DeviceType__c;
    
        if ('FLAT_AUDIO'.equalsIgnoreCase(selectedFlat)) {
            return !'FlatAudio'.equalsIgnoreCase(deviceType);
        }
    
        if ('FLAT_AUDIO_VIDEO'.equalsIgnoreCase(selectedFlat)) {
            return !'FlatAudioVideo'.equalsIgnoreCase(deviceType);
        }
    
        return false;
    }
    
    @TestVisible
    private static Boolean isBarRistorantiConfig(SIAE_DirittiConnessiConfig__mdt config) {
        return config != null && 'Bar_Ristoranti'.equalsIgnoreCase(config.DeveloperName);
    }
    
    @TestVisible
    private static Decimal applyBarRistorantiFlatMaggiorazioni(
        Decimal importoRiga,
        SIAE_DirittiConnessiConfig__mdt config,
        RCASalesTransaction.ItemNode itemNode,
        SIAE_DirittiConnessiRule__c regola
    ) {
        if (importoRiga == null) {
            return 0;
        }
    
        if (!isBarRistorantiFlatBaseRule(config, itemNode, regola)) {
            return importoRiga;
        }
    
        Decimal coeffMq = coeffOrOne(itemNode.coeffMaggiorazioneMQ);
        Decimal coeffAreeEsterne = coeffOrOne(itemNode.coeffAreeEsterne);

		Decimal result = importoRiga * coeffAreeEsterne;
    
        System.debug(
            LoggingLevel.WARN,
            'DC Bar/Ristoranti flat maggiorazioni -> ' +
            'typeOfFlatRate=' + itemNode.typeOfFlatRate +
            ', deviceType=' + regola.SIAE_DeviceType__c +
            ', base=' + importoRiga +
            ', coeffMq=' + coeffMq +
            ', coeffAreeEsterne=' + coeffAreeEsterne +
            ', result=' + result
        );
    
        return result;
    }
    
    @TestVisible
    private static Boolean isBarRistorantiFlatBaseRule(
        SIAE_DirittiConnessiConfig__mdt config,
        RCASalesTransaction.ItemNode itemNode,
        SIAE_DirittiConnessiRule__c regola
    ) {
        if (
            !isBarRistorantiConfig(config) ||
            itemNode == null ||
            regola == null ||
            String.isBlank(itemNode.typeOfFlatRate)
        ) {
            return false;
        }
    
        if (!'TARIFFA_BASE'.equalsIgnoreCase(regola.SIAE_Action__c)) {
            return false;
        }
    
        return isSelectedBarRistorantiFlatDeviceType(
            itemNode.typeOfFlatRate,
            regola.SIAE_DeviceType__c
        );
    }
    
    @TestVisible
    private static Boolean isSelectedBarRistorantiFlatDeviceType(
        String typeOfFlatRate,
        String deviceType
    ) {
        if (String.isBlank(typeOfFlatRate) || String.isBlank(deviceType)) {
            return false;
        }
    
        if ('FLAT_AUDIO'.equalsIgnoreCase(typeOfFlatRate)) {
            return 'FlatAudio'.equalsIgnoreCase(deviceType);
        }
    
        if ('FLAT_AUDIO_VIDEO'.equalsIgnoreCase(typeOfFlatRate)) {
            return 'FlatAudioVideo'.equalsIgnoreCase(deviceType);
        }
    
        return false;
    }
    
    private static Decimal coeffOrOne(Decimal coeff) {
        return coeff == null ? 1 : coeff;
    }

    /**
     * Risolve il coefficiente di stagionalità da applicare alla riga DC.
     *
     * Il nodo porta in dote il coefficiente dei Diritti d'Autore
     * (SIAE_CoeffStagionalita__c, calcolato dalla PreHook su
     * SIAE_ConfigurazionePricing__c). La tariffa che ha fatto match espone tre
     * coefficienti DC indipendenti, uno per copertura:
     * - Annuale     -> SIAE_CoeffStagionalitaDC__c
     * - Semestrale  -> SIAE_CoeffStagionalitaDC_Semestrale__c
     * - Trimestrale -> SIAE_CoeffStagionalitaDC_Trimestrale__c
     *
     * Se la copertura corrente ha il proprio coefficiente valorizzato sulla
     * tariffa, quello sostituisce il coefficiente Diritti d'Autore. Se non è
     * valorizzato (o la copertura è Mensile/non gestita), resta il
     * coefficiente Diritti d'Autore, così che le tariffe senza coefficiente DC
     * mantengano il comportamento attuale.
     */
    @TestVisible
    private static Decimal resolveSeasonalityCoefficient(
        RCASalesTransaction.ItemNode itemNode,
        SIAE_DirittiConnessiTariffa__c tariffa
    ) {
        Decimal coeffDirittiAutore = itemNode == null
            ? 1
            : coeffOrOne(itemNode.periodicityCoefficient);

        if (tariffa == null) {
            return coeffDirittiAutore;
        }

        String copertura = itemNode == null || String.isBlank(itemNode.typeCoverage)
            ? COVERAGE_ANNUALE
            : itemNode.typeCoverage.trim();

        Decimal coeffDC;
        if (COVERAGE_ANNUALE.equalsIgnoreCase(copertura)) {
            coeffDC = tariffa.SIAE_CoeffStagionalitaDC__c;
        } else if (COVERAGE_SEMESTRALE.equalsIgnoreCase(copertura)) {
            coeffDC = tariffa.SIAE_CoeffStagionalitaDC_Semestrale__c;
        } else if (COVERAGE_TRIMESTRALE.equalsIgnoreCase(copertura)) {
            coeffDC = tariffa.SIAE_CoeffStagionalitaDC_Trimestrale__c;
        }

        return coeffDC != null ? coeffDC : coeffDirittiAutore;
    }

    @TestVisible
    private static void enrichAcconciatori(Map<String, String> attrs) {
        if (attrs == null || attrs.isEmpty()) {
            return;
        }
    
        Decimal radio = parseDecimal(attrs.get('SIAE-ATTR-RADIO'));
        Decimal tvUnd40 = parseDecimal(attrs.get('SIAE-ATTR-TV-UND40'));
        Decimal tvOvr40 = parseDecimal(attrs.get('SIAE-ATTR-TV-OVR40'));
    
        if (radio == null) {
            radio = 0;
        }
    
        if (tvUnd40 == null) {
            tvUnd40 = 0;
        }
    
        if (tvOvr40 == null) {
            tvOvr40 = 0;
        }
    
        Decimal totalTv = tvUnd40 + tvOvr40;
    
        if (radio <= 0 || totalTv <= 0) {
            return;
        }
    
        /*
         * RadioPiuTv serve solo per attivare la tariffa base combinata.
         * Non azzeriamo radio/tv perché le maggiorazioni devono essere gestite
         * dai record originali con DeviceGroupKey.
         */
        attrs.put('RadioPiuTv', '1');
    }

    @TestVisible
    private static Boolean shouldSkipAcconciatoriStandaloneRadioTvRule(
        SIAE_DirittiConnessiConfig__mdt config,
        SIAE_DirittiConnessiRule__c regola,
        Map<String, String> attrs
    ) {
        if (
            config == null ||
            config.DeveloperName != 'Acconciatori' ||
            regola == null ||
            attrs == null ||
            attrs.isEmpty()
        ) {
            return false;
        }
    
        Decimal radioPiuTv = parseDecimal(attrs.get('RadioPiuTv'));
    
        if (radioPiuTv == null || radioPiuTv <= 0) {
            return false;
        }
    
        /*
         * Quando esiste RadioPiuTV, la base standalone Radio/TV non deve entrare,
         * perché viene sostituita dalla base combinata 0794.
         *
         * Le maggiorazioni invece devono restare attive:
         * - radio extra
         * - TV extra
         * - altoparlanti radio
         * - altoparlanti TV
         * - TV > 40
         */
        Boolean isStandaloneRadioOrTvBase =
            regola.SIAE_Action__c == 'TARIFFA_BASE' &&
            (
                regola.SIAE_RevenueItemDC__c == '0792' ||
                regola.SIAE_RevenueItemDC__c == '0793'
            );
    
        if (isStandaloneRadioOrTvBase) {
            System.debug(
                LoggingLevel.WARN,
                'DC SKIP RadioPiuTV standalone base -> ' +
                'name=' + regola.Name +
                ', action=' + regola.SIAE_Action__c +
                ', revenue=' + regola.SIAE_RevenueItemDC__c +
                ', deviceType=' + regola.SIAE_DeviceType__c
            );
    
            return true;
        }
    
        /*
         * I vecchi record virtuali RadioPiuTV extra non devono più entrare.
         * Le extra sono gestite dai record originali con DeviceGroupKey.
         */
        Set<String> virtualRadioPiuTvExtraAttrs = new Set<String>{
            'RadioPiuTvRadioExtra',
            'RadioPiuTvTvExtra',
            'RadioPiuTvTvOvr40Count'
        };
    
        if (
            String.isNotBlank(regola.SIAE_AttributeQuantity__c) &&
            virtualRadioPiuTvExtraAttrs.contains(regola.SIAE_AttributeQuantity__c.trim())
        ) {
            System.debug(
                LoggingLevel.WARN,
                'DC SKIP RadioPiuTV virtual extra rule -> ' +
                'name=' + regola.Name +
                ', quantityAttr=' + regola.SIAE_AttributeQuantity__c +
                ', revenue=' + regola.SIAE_RevenueItemDC__c
            );
    
            return true;
        }
    
        return false;
    }

    @TestVisible
    private static Boolean conditionMatches(
        SIAE_DirittiConnessiRule__c rule,
        Map<String, String> mapAttributeCodeAttributeValue
    ) {
        if (rule == null) {
            return false;
        }

        String op = rule.SIAE_Operator__c;

        if (op == 'ALWAYS') {
            return true;
        }

        if (op == 'EQ_TOTAL') {
            if (String.isBlank(rule.SIAE_AttributeQuantityList__c)) {
                return false;
            }

            Decimal total = 0;

            for (String code : rule.SIAE_AttributeQuantityList__c.split(';')) {
                Decimal q = parseDecimal(mapAttributeCodeAttributeValue.get(code.trim()));

                if (q != null) {
                    total += q;
                }
            }

            Decimal expected = parseDecimal(rule.SIAE_ValueFrom__c);

            return expected != null && total == expected;
        }

        if (op == 'EQ_EXCLUSIVE') {
            // Uso esclusivo di un solo tipo di dispositivo (es. "sola radio in luogo comune"):
            // - il dispositivo primario (SIAE_Attribute__c) deve essere presente (>= 1);
            // - tutti gli altri dispositivi elencati in SIAE_AttributeQuantityList__c
            //   devono essere assenti (somma == 0).
            Decimal primary = parseDecimal(
                mapAttributeCodeAttributeValue.get(rule.SIAE_Attribute__c)
            );

            if (primary == null || primary < 1) {
                return false;
            }

            if (String.isBlank(rule.SIAE_AttributeQuantityList__c)) {
                return false;
            }

            Decimal othersTotal = 0;

            for (String code : rule.SIAE_AttributeQuantityList__c.split(';')) {
                Decimal q = parseDecimal(mapAttributeCodeAttributeValue.get(code.trim()));

                if (q != null) {
                    othersTotal += q;
                }
            }

            return othersTotal == 0;
        }

        String attributeCode = rule.SIAE_Attribute__c;

        if (
            String.isBlank(attributeCode) ||
            mapAttributeCodeAttributeValue == null ||
            !mapAttributeCodeAttributeValue.containsKey(attributeCode)
        ) {
            return false;
        }

        String attributeValue = mapAttributeCodeAttributeValue.get(attributeCode);
        String valueFrom = rule.SIAE_ValueFrom__c;
        String valueTo = rule.SIAE_ValueTo__c;

        if (op == 'EQ') {
            Decimal attrDec = parseDecimal(attributeValue);
            Decimal fromDec = parseDecimal(valueFrom);

            if (attrDec != null && fromDec != null) {
                return attrDec == fromDec;
            }

            return attributeValue != null && attributeValue.equalsIgnoreCase(valueFrom);
        }

        if (op == 'IN') {
            if (String.isBlank(valueFrom)) {
                return false;
            }

            Set<String> valueAllowed = new Set<String>();

            for (String value : valueFrom.toLowerCase().split(',')) {
                valueAllowed.add(value.trim());
            }

            return attributeValue != null &&
                valueAllowed.contains(attributeValue.toLowerCase().trim());
        }

        Decimal attributeValueDecimal = parseDecimal(attributeValue);

        if (attributeValueDecimal == null) {
            return false;
        }

        if (op == 'LTE') {
            Decimal treshold = parseDecimal(valueFrom);
            return treshold != null && attributeValueDecimal <= treshold;
        }

        if (op == 'GT') {
            Decimal treshold = parseDecimal(valueFrom);
            return treshold != null && attributeValueDecimal > treshold;
        }

        if (op == 'BETWEEN') {
            Decimal valueFromDecimal = parseDecimal(valueFrom);
            Decimal valueToDecimal = parseDecimal(valueTo);

            return valueFromDecimal != null &&
                valueToDecimal != null &&
                attributeValueDecimal >= valueFromDecimal &&
                attributeValueDecimal <= valueToDecimal;
        }

        return false;
    }

    /*@TestVisible
    private static Decimal getRate(
        String configName,
        String deviceType,
        Decimal tresholdValue,
        String secondaryValue,
        List<SIAE_DirittiConnessiTariffa__c> listOfRate
    ) {
        if (
            String.isBlank(configName) ||
            String.isBlank(deviceType) ||
            tresholdValue == null ||
            listOfRate == null ||
            listOfRate.isEmpty()
        ) {
            return null;
        }

        for (SIAE_DirittiConnessiTariffa__c t : listOfRate) {
            if (t == null) {
                continue;
            }

            if (t.SIAE_ConfigName__c != configName) {
                continue;
            }

            if (t.SIAE_DeviceType__c != deviceType) {
                continue;
            }

            if (String.isBlank(secondaryValue)) {
                if (String.isNotBlank(t.SIAE_SecondaryParameterValue__c)) {
                    continue;
                }
            } else {
                if (t.SIAE_SecondaryParameterValue__c != secondaryValue) {
                    continue;
                }
            }

            Decimal fromVal = t.SIAE_BracketFrom__c;
            Decimal toVal = t.SIAE_BracketTo__c;

            if (
                fromVal != null &&
                tresholdValue >= fromVal &&
                (toVal == null || tresholdValue <= toVal)
            ) {
                return t.SIAE_Amount__c;
            }
        }

        return null;
    }*/
    
    /**
     * Esito della risoluzione di una tariffa: l'importo calcolato più il record
     * che lo ha prodotto. Il record serve a leggere il coefficiente di
     * stagionalità DC, che getRate() da sola scarterebbe.
     */
    @TestVisible
    private class RateResolution {
        public SIAE_DirittiConnessiTariffa__c tariffa;
        public Decimal amount;

        public RateResolution(SIAE_DirittiConnessiTariffa__c tariffa, Decimal amount) {
            this.tariffa = tariffa;
            this.amount = amount;
        }
    }

    //FIX RATE BAR MQ > 500
    @TestVisible
    private static Decimal getRate(
        String configName,
        String deviceType,
        Decimal tresholdValue,
        String secondaryValue,
        List<SIAE_DirittiConnessiTariffa__c> listOfRate
    ) {
        RateResolution resolution = resolveRate(
            configName,
            deviceType,
            tresholdValue,
            secondaryValue,
            listOfRate
        );

        return resolution == null ? null : resolution.amount;
    }

    @TestVisible
    private static RateResolution resolveRate(
        String configName,
        String deviceType,
        Decimal tresholdValue,
        String secondaryValue,
        List<SIAE_DirittiConnessiTariffa__c> listOfRate
    ) {
        if (
            String.isBlank(configName) ||
            String.isBlank(deviceType) ||
            tresholdValue == null ||
            listOfRate == null ||
            listOfRate.isEmpty()
        ) {
            return null;
        }
    
        SIAE_DirittiConnessiTariffa__c ultimoScaglione = null;
        Decimal maxBracketTo = -1;
        Decimal maxBracketFrom = -1;
    
        for (SIAE_DirittiConnessiTariffa__c t : listOfRate) {
            if (t == null) {
                continue;
            }
    
            if (t.SIAE_ConfigName__c != configName) {
                continue;
            }
    
            if (t.SIAE_DeviceType__c != deviceType) {
                continue;
            }
    
            if (String.isBlank(secondaryValue)) {
                if (String.isNotBlank(t.SIAE_SecondaryParameterValue__c)) {
                    continue;
                }
            } else {
                if (t.SIAE_SecondaryParameterValue__c != secondaryValue) {
                    continue;
                }
            }
    
            Decimal fromVal = t.SIAE_BracketFrom__c != null
                ? t.SIAE_BracketFrom__c
                : 0;

            Decimal toVal = t.SIAE_BracketTo__c;

            if (
                tresholdValue >= fromVal &&
                (toVal == null || tresholdValue <= toVal)
            ) {
                return new RateResolution(t, t.SIAE_Amount__c);
            }
    
            /*
             * Tracciamo l'ultimo scaglione chiuso.
             * Serve per calcolare la maggiorazione oltre la soglia massima.
             *
             * Esempio:
             * 251 - 500 con ExtraUnitSize = 100 e ExtraPercentage = 0.1
             */
            if (toVal != null) {
                if (
                    ultimoScaglione == null ||
                    toVal > maxBracketTo ||
                    (toVal == maxBracketTo && fromVal > maxBracketFrom)
                ) {
                    ultimoScaglione = t;
                    maxBracketTo = toVal;
                    maxBracketFrom = fromVal;
                }
            }
        }
    
        /*
         * Se non ho trovato uno scaglione contenente il valore,
         * provo a usare l'ultimo scaglione e applicare l'extra oltre soglia.
         */
        if (ultimoScaglione == null) {
            return null;
        }
    
        Decimal baseAmount = ultimoScaglione.SIAE_Amount__c != null
            ? ultimoScaglione.SIAE_Amount__c
            : 0;
    
        Decimal sogliaMassima = ultimoScaglione.SIAE_BracketTo__c;

        if (sogliaMassima == null || tresholdValue <= sogliaMassima) {
            return new RateResolution(ultimoScaglione, baseAmount);
        }

        Decimal extraUnitSize = ultimoScaglione.SIAE_ExtraUnitSize__c;

        if (extraUnitSize == null || extraUnitSize <= 0) {
            return new RateResolution(ultimoScaglione, baseAmount);
        }
    
        Decimal extraAmountPerUnit = 0;
    
        if (
            ultimoScaglione.SIAE_ExtraAmountPerUnit__c != null &&
            ultimoScaglione.SIAE_ExtraAmountPerUnit__c != 0
        ) {
            extraAmountPerUnit = ultimoScaglione.SIAE_ExtraAmountPerUnit__c;
        } else if (
            ultimoScaglione.SIAE_ExtraPercentage__c != null &&
            ultimoScaglione.SIAE_ExtraPercentage__c != 0
        ) {
            extraAmountPerUnit = baseAmount * ultimoScaglione.SIAE_ExtraPercentage__c;
        }
    
        if (extraAmountPerUnit == 0) {
            return new RateResolution(ultimoScaglione, baseAmount);
        }

        Decimal eccedenza = tresholdValue - sogliaMassima;
        Decimal unitaExtra = Decimal.valueOf((Integer)Math.ceil(eccedenza / extraUnitSize));
    
        Decimal finalAmount = baseAmount + (unitaExtra * extraAmountPerUnit);
    
        System.debug(
            LoggingLevel.WARN,
            'DC getRate extra oltre scaglione -> ' +
            'configName=' + configName +
            ', deviceType=' + deviceType +
            ', threshold=' + tresholdValue +
            ', baseAmount=' + baseAmount +
            ', sogliaMassima=' + sogliaMassima +
            ', extraUnitSize=' + extraUnitSize +
            ', extraAmountPerUnit=' + extraAmountPerUnit +
            ', unitaExtra=' + unitaExtra +
            ', finalAmount=' + finalAmount
        );

        return new RateResolution(ultimoScaglione, finalAmount);
    }
    
    

    @TestVisible
    private static SIAE_DirittiConnessiTariffa__c getLastTreshold(
        List<SIAE_DirittiConnessiTariffa__c> listOfRate,
        String configName,
        String deviceType,
        String secondaryValue
    ) {
        SIAE_DirittiConnessiTariffa__c lastOption = null;
        Decimal maxValue = -1;

        if (listOfRate == null || listOfRate.isEmpty()) {
            return null;
        }

        for (SIAE_DirittiConnessiTariffa__c t : listOfRate) {
            if (t == null) {
                continue;
            }

            if (t.SIAE_ConfigName__c != configName || t.SIAE_DeviceType__c != deviceType) {
                continue;
            }

            if (String.isBlank(secondaryValue)) {
                if (String.isNotBlank(t.SIAE_SecondaryParameterValue__c)) {
                    continue;
                }
            } else {
                if (t.SIAE_SecondaryParameterValue__c != secondaryValue) {
                    continue;
                }
            }

            Decimal valueFrom = t.SIAE_BracketTo__c != null
                ? t.SIAE_BracketTo__c
                : 999999;

            if (valueFrom > maxValue) {
                maxValue = valueFrom;
                lastOption = t;
            }
        }

        return lastOption;
    }

    @TestVisible
    private static Map<String, SIAE_DirittiConnessiTariffa__c> buildTariffeIndex(
        List<SIAE_DirittiConnessiTariffa__c> tariffe
    ) {
        Map<String, SIAE_DirittiConnessiTariffa__c> idx =
            new Map<String, SIAE_DirittiConnessiTariffa__c>();

        if (tariffe == null || tariffe.isEmpty()) {
            return idx;
        }

        for (SIAE_DirittiConnessiTariffa__c t : tariffe) {
            if (t == null) {
                continue;
            }

            String secParam = String.isNotBlank(t.SIAE_SecondaryParameterValue__c)
                ? t.SIAE_SecondaryParameterValue__c
                : 'NONE';

            String key =
                t.SIAE_ConfigName__c + '|' +
                t.SIAE_DeviceType__c + '|' +
                secParam + '|' +
                t.SIAE_BracketFrom__c + '|' +
                t.SIAE_BracketTo__c;

            idx.put(key, t);
        }

        return idx;
    }

    @TestVisible
    private static Decimal calculateLineItemPrice(
        SIAE_DirittiConnessiRule__c rule,
        Decimal rate,
        Integer attributeValue,
        Decimal tresholdValue,
        String configName,
        List<SIAE_DirittiConnessiTariffa__c> listOfRate,
        Decimal totaleRighe
    ) {
        if (rule == null || rate == null || attributeValue == null || attributeValue <= 0) {
            return 0;
        }

        String action = rule.SIAE_Action__c;

        Decimal actionValue = rule.SIAE_ActionValue__c != null
            ? rule.SIAE_ActionValue__c
            : 0;

        if (action == 'TARIFFA_BASE') {
            return rate * attributeValue;
        }

        if (action == 'MAGGIORAZIONE_PCT') {
            return (rate * (actionValue / 100)) * attributeValue;
        }

        if (action == 'MAGGIORAZIONE_FLAT') {
            return actionValue * attributeValue;
        }

        if (action == 'RIDUZIONE_PCT') {
            return rate * ((100 - actionValue) / 100) * attributeValue;
        }

        if (action == 'RIDUZIONE_FLAT') {
            return -actionValue * attributeValue;
        }

        if (action == 'MOLTIPLICATORE') {
            return rate * (actionValue - 1) * attributeValue;
        }

        if (action == 'SCONTO_SUL_TOTALE_PCT') {
            Decimal total = totaleRighe == null ? 0 : totaleRighe;
            return -(total * (actionValue / 100));
        }

        return 0;
    }

    @TestVisible
    private static Decimal getTresholdValue(
        SIAE_DirittiConnessiRule__c rule,
        Map<String, String> mapAttributeCodeAttributeValue
    ) {
        if (rule == null) {
            return 0;
        }

        String tresholdAttribute = String.isNotBlank(rule.SIAE_AttributeTreshold__c)
            ? rule.SIAE_AttributeTreshold__c
            : rule.SIAE_Attribute__c;

        if (String.isBlank(tresholdAttribute)) {
            return 0;
        }

        Decimal value = parseDecimal(mapAttributeCodeAttributeValue.get(tresholdAttribute));

        return value == null ? 0 : value;
    }

    @TestVisible
    private static Integer getQuantity(
        SIAE_DirittiConnessiRule__c rule,
        Map<String, String> mapAttributeCodeAttributeValue
    ) {
        if (rule == null) {
            return 0;
        }

        if (mapAttributeCodeAttributeValue == null) {
            mapAttributeCodeAttributeValue = new Map<String, String>();
        }

        // Per EQ_EXCLUSIVE la lista SIAE_AttributeQuantityList__c contiene i dispositivi
        // che devono essere ASSENTI (usati solo dalla condizione): la quantità della riga
        // deriva quindi dal dispositivo primario (es. numero di radio), non dalla lista.
        if (rule.SIAE_Operator__c == 'EQ_EXCLUSIVE') {
            Decimal q = parseDecimal(
                mapAttributeCodeAttributeValue.get(rule.SIAE_Attribute__c)
            );

            return q != null ? q.intValue() : 0;
        }

        if (String.isNotBlank(rule.SIAE_AttributeQuantityList__c)) {
            Decimal total = 0;

            for (String code : rule.SIAE_AttributeQuantityList__c.split(';')) {
                Decimal q = parseDecimal(mapAttributeCodeAttributeValue.get(code.trim()));

                if (q != null) {
                    total += q;
                }
            }

            return total.intValue();
        }

        if (String.isNotBlank(rule.SIAE_AttributeQuantity__c)) {
            Decimal q = parseDecimal(
                mapAttributeCodeAttributeValue.get(rule.SIAE_AttributeQuantity__c)
            );

            return q != null
                ? q.intValue()
                : 0;
        }

        return 1;
    }

    @TestVisible
    private static Decimal parseDecimal(String value) {
        if (String.isBlank(value)) {
            return null;
        }

        try {
            return Decimal.valueOf(value.trim().replace(',', '.'));
        } catch (Exception e) {
            return null;
        }
    }
}