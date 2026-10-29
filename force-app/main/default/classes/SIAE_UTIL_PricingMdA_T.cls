/**
 * @description       : Test class per SIAE_UTIL_PricingMdA
 * @author            : Domenico Del Prete - domenico.delprete@nttdata.com
 * @group             : NTT Data
 * @last modified on  : 04-08-2026
 * @last modified by  : Gaetano Iuliano - gaetano.iuliano@nttdata.com
**/
@isTest
public class SIAE_UTIL_PricingMdA_T {

    /**
     * @description Metodo di utilità per creare una configurazione in memoria
     * senza necessità di DML.
     */
    private static SIAE_ConfigurazionePricing__c getMockConfig() {
        return new SIAE_ConfigurazionePricing__c(
            SIAE_UsaDefaultTypeCoverage__c = true,
            SIAE_DefaultTypeCoverageValue__c = 'Mensile',

            SIAE_CoeffStag_Annuale__c = 1.0,
            SIAE_CoeffStag_Semestrale__c = 0.6,
            SIAE_CoeffStag_Trimestrale__c = 0.35,
            SIAE_CoeffStag_Mensile__c = 0.15,

            SIAE_UsaMaggiorazioneEsterna__c = true,
            SIAE_AreeEsterne_ValoreFino50__c = 1.1,
            SIAE_AreeEsterne_ValoreOltre50__c = 1.25,

            SIAE_UsaMaggiorazioneMQ__c = true,
            SIAE_MQ_SogliaBase__c = 500,
            SIAE_MQ_Tranche__c = 100,
            SIAE_MQ_IncrementoPerTranche__c = 0.1,
            SIAE_MQ_CoeffBase__c = 1.0,

            SIAE_UsaMaggiorazioneDipendenti__c = true,
            SIAE_Dip_SogliaBase__c = 200,
            SIAE_Dip_Tranche__c = 50,
            SIAE_Dip_ImportoRadio__c = 10,
            SIAE_Dip_ImportoAudio__c = 20,
            SIAE_Dip_ImportoVideo__c = 30,

            SIAE_UsaMaggiorazioneTV40__c = true,
            SIAE_TV40_Coefficiente__c = 1.5,

            SIAE_UsaFlat__c = true,
            SIAE_AggiungiAFLAT__c = 'SIAE-ATTR-JUKEBOX;SIAE-ATTR-VIDEO-JUKEBOX;SIAE-ATTR-KARAOKE',
            SIAE_EscludiFlatAudio__c = 'SIAE-ATTR-RADIOINSTORE'
        );
    }

    private static Map<String, Object> getMockFlatSourceItem() {
        Map<String, Object> sourceItem = new Map<String, Object>();

        sourceItem.put('SIAE_FlatAudio__c', 100);
        sourceItem.put('SIAE_FlatVideo__c', 200);

        List<Object> attributes = new List<Object>();

        attributes.add(new Map<String, Object>{
            'AttributeDefinitionCode' => 'SIAE-ATTR-JUKEBOX',
            'AttributeValue' => '1',
            'SIAE_DeviceTotalPrice' => 50
        });

        attributes.add(new Map<String, Object>{
            'AttributeDefinitionCode' => 'SIAE-ATTR-KARAOKE',
            'AttributeValue' => '0',
            'SIAE_DeviceTotalPrice' => 90
        });

        attributes.add(new Map<String, Object>{
            'AttributeDefinitionCode' => 'SIAE-ATTR-RADIO',
            'AttributeValue' => '2',
            'SIAE_DeviceTotalPrice' => 80
        });

        sourceItem.put('SalesTransactionItemAttribute', attributes);

        return sourceItem;
    }

    @isTest
    static void testEntePubblicoMaggiorazione() {
        // isEntePubblico
        System.assert(SIAE_UTIL_PricingMdA.isEntePubblico('SI'), 'SI -> ente pubblico');
        System.assert(SIAE_UTIL_PricingMdA.isEntePubblico('si'), 'case-insensitive');
        System.assert(!SIAE_UTIL_PricingMdA.isEntePubblico('NO'), 'NO -> no');
        System.assert(!SIAE_UTIL_PricingMdA.isEntePubblico(null), 'null -> no');

        // azzera maggiorazione quando ente pubblico
        Map<String, Decimal> importi = new Map<String, Decimal>{ 'radio' => 247.5, 'audio' => 705.3, 'video' => 711.45 };
        SIAE_UTIL_PricingMdA.azzeraMaggiorazioneDipSeEntePubblico(importi, 'SI');
        System.assertEquals(0, importi.get('radio'), 'radio azzerato');
        System.assertEquals(0, importi.get('audio'), 'audio azzerato');
        System.assertEquals(0, importi.get('video'), 'video azzerato');

        // NO -> invariato
        Map<String, Decimal> importi2 = new Map<String, Decimal>{ 'radio' => 247.5, 'audio' => 705.3, 'video' => 711.45 };
        SIAE_UTIL_PricingMdA.azzeraMaggiorazioneDipSeEntePubblico(importi2, 'NO');
        System.assertEquals(247.5, importi2.get('radio'), 'radio invariato con NO');

        // null map -> nessuna eccezione
        SIAE_UTIL_PricingMdA.azzeraMaggiorazioneDipSeEntePubblico(null, 'SI');
    }

    @isTest
    static void testDefaultTypeCoverage() {
        SIAE_ConfigurazionePricing__c conf = getMockConfig();

        String res1 = SIAE_UTIL_PricingMdA.defaultTypeCoverage('Semestrale', conf);
        System.assertEquals('Semestrale', res1, 'Dovrebbe mantenere il valore corrente');

        String res2 = SIAE_UTIL_PricingMdA.defaultTypeCoverage('', conf);
        System.assertEquals('Mensile', res2, 'Dovrebbe prendere il valore di default dalla configurazione');

        String res3 = SIAE_UTIL_PricingMdA.defaultTypeCoverage(null, null);
        System.assertEquals('Annuale', res3, 'Dovrebbe applicare il fallback Annuale');
    }

    @isTest
    static void testCoeffStagionalita() {
        SIAE_ConfigurazionePricing__c conf = getMockConfig();

        System.assertEquals(1.0, SIAE_UTIL_PricingMdA.coeffStagionalita('Annuale', conf), 'Coeff Annuale errato');
        System.assertEquals(0.6, SIAE_UTIL_PricingMdA.coeffStagionalita('Semestrale', conf), 'Coeff Semestrale errato');
        System.assertEquals(0.35, SIAE_UTIL_PricingMdA.coeffStagionalita('Trimestrale', conf), 'Coeff Trimestrale errato');
        System.assertEquals(0.15, SIAE_UTIL_PricingMdA.coeffStagionalita('Mensile', conf), 'Coeff Mensile errato');

        // Annuale con data: pro-rata sui mesi residui dell'anno (13 - mese)
        System.assertEquals(1.0, SIAE_UTIL_PricingMdA.coeffStagionalita('Annuale', conf, Date.newInstance(2026, 1, 15)), 'Coeff Annuale con Date gennaio errato');
        System.assertEquals(0.5, SIAE_UTIL_PricingMdA.coeffStagionalita('Annuale', conf, Date.newInstance(2026, 7, 15)), 'Coeff Annuale con Date luglio errato');
        System.assertEquals(0.25, SIAE_UTIL_PricingMdA.coeffStagionalita('Annuale', conf, Date.newInstance(2026, 10, 15)), 'Coeff Annuale con Date ottobre errato');
        // Le altre coperture ignorano la data
        System.assertEquals(0.6, SIAE_UTIL_PricingMdA.coeffStagionalita('Semestrale', conf, Date.newInstance(2026, 7, 15)), 'Coeff Semestrale con Date errato');

        System.assertEquals(1.0, SIAE_UTIL_PricingMdA.coeffStagionalita('', conf), 'Fallback per stringa vuota errato');
        System.assertEquals(1.0, SIAE_UTIL_PricingMdA.coeffStagionalita('ValoreSbagliato', conf), 'Fallback per stringa errata errato');
        System.assertEquals(1.0, SIAE_UTIL_PricingMdA.coeffStagionalita('Annuale', null), 'Fallback per conf nulla errato');
    }

    @isTest
    static void testFattoreMaggiorazioneEsterna() {
        SIAE_ConfigurazionePricing__c conf = getMockConfig();

        System.assertEquals(1.1, SIAE_UTIL_PricingMdA.fattoreMaggiorazioneEsterna('Si, fino a 50 mq', conf), 'Maggiorazione fino a 50 mq errata');
        System.assertEquals(1.25, SIAE_UTIL_PricingMdA.fattoreMaggiorazioneEsterna('Si, oltre 50 mq', conf), 'Maggiorazione oltre 50 mq errata');

        conf.SIAE_UsaMaggiorazioneEsterna__c = false;
        System.assertEquals(1.0, SIAE_UTIL_PricingMdA.fattoreMaggiorazioneEsterna('Si, fino a 50 mq', conf), 'Se usaMaggiorazione=false, deve tornare 1.0');

        System.assertEquals(1.0, SIAE_UTIL_PricingMdA.fattoreMaggiorazioneEsterna('No', getMockConfig()), 'Se valore è No, deve tornare 1.0');
        System.assertEquals(1.0, SIAE_UTIL_PricingMdA.fattoreMaggiorazioneEsterna(null, getMockConfig()), 'Se valore è null, deve tornare 1.0');
        System.assertEquals(1.0, SIAE_UTIL_PricingMdA.fattoreMaggiorazioneEsterna('Si, fino a 50 mq', null), 'Se conf è null, deve tornare 1.0');
    }

    @isTest
    static void testFattoreMQOltre500() {
        SIAE_ConfigurazionePricing__c conf = getMockConfig();

        System.assertEquals(1.2, SIAE_UTIL_PricingMdA.fattoreMQOltre500(650, conf), 'Calcolo MQ oltre 500 errato');
        System.assertEquals(1.0, SIAE_UTIL_PricingMdA.fattoreMQOltre500(300, conf), 'Sotto la soglia base deve essere 1.0');
        System.assertEquals(1.0, SIAE_UTIL_PricingMdA.fattoreMQOltre500(null, conf), 'MQ Null deve tornare 1.0');
        System.assertEquals(1.0, SIAE_UTIL_PricingMdA.fattoreMQOltre500(800, null), 'Conf Null deve tornare 1.0');

        conf.SIAE_UsaMaggiorazioneMQ__c = false;
        System.assertEquals(1.0, SIAE_UTIL_PricingMdA.fattoreMQOltre500(800, conf), 'Se flag falso deve tornare 1.0');
    }

    @isTest
    static void testImportoDipendentiOltre200() {
        SIAE_ConfigurazionePricing__c conf = getMockConfig();

        Map<String, Decimal> res1 = SIAE_UTIL_PricingMdA.importoDipendentiOltre200(310, conf);
        System.assertEquals(30.0, res1.get('radio'), 'Importo radio errato');
        System.assertEquals(60.0, res1.get('audio'), 'Importo audio errato');
        System.assertEquals(90.0, res1.get('video'), 'Importo video errato');

        Map<String, Decimal> res2 = SIAE_UTIL_PricingMdA.importoDipendentiOltre200(150, conf);
        System.assertEquals(0.0, res2.get('radio'), 'Sotto soglia deve essere 0');

        Map<String, Decimal> res3 = SIAE_UTIL_PricingMdA.importoDipendentiOltre200(null, conf);
        System.assertEquals(0.0, res3.get('radio'), 'Valore null deve essere 0');

        Map<String, Decimal> res4 = SIAE_UTIL_PricingMdA.importoDipendentiOltre200(300, null);
        System.assertEquals(0.0, res4.get('radio'), 'Conf null deve essere 0');

        conf.SIAE_UsaMaggiorazioneDipendenti__c = false;
        Map<String, Decimal> res5 = SIAE_UTIL_PricingMdA.importoDipendentiOltre200(300, conf);
        System.assertEquals(0.0, res5.get('radio'), 'Se flag off deve essere 0');
    }

    @isTest
    static void testFattoreTV40() {
        SIAE_ConfigurazionePricing__c conf = getMockConfig();

        System.assertEquals(1.5, SIAE_UTIL_PricingMdA.fattoreTV40(conf), 'Dovrebbe applicare il coefficiente configurato');
        System.assertEquals(1.0, SIAE_UTIL_PricingMdA.fattoreTV40(null), 'Con conf a null deve essere 1.0');

        conf.SIAE_UsaMaggiorazioneTV40__c = false;
        System.assertEquals(1.0, SIAE_UTIL_PricingMdA.fattoreTV40(conf), 'Con flag falso deve essere 1.0');
    }

    @isTest
    static void testParseMethods() {
        System.assertEquals(12.5, SIAE_UTIL_PricingMdA.parseDecimal('12.5'), 'Parse decimale valido fallito');
        System.assertEquals(12.5, SIAE_UTIL_PricingMdA.parseDecimal('12,5'), 'Parse decimale con virgola valido fallito');
        System.assertEquals(null, SIAE_UTIL_PricingMdA.parseDecimal(null), 'Parse decimale null fallito');
        System.assertEquals(null, SIAE_UTIL_PricingMdA.parseDecimal('not-a-number'), 'Parse decimale stringa errata fallito');

        System.assertEquals(12, SIAE_UTIL_PricingMdA.parseInteger('12'), 'Parse intero valido fallito');
        System.assertEquals(12, SIAE_UTIL_PricingMdA.parseInteger('12.8'), 'Parse intero con decimale fallito');
        System.assertEquals(null, SIAE_UTIL_PricingMdA.parseInteger(''), 'Parse intero stringa vuota fallito');
        System.assertEquals(null, SIAE_UTIL_PricingMdA.parseInteger('abc'), 'Parse intero stringa errata fallito');
    }

    @isTest
    static void testCalcMesiResidui() {
        Date july = Date.newInstance(Date.today().year(), 7, 1);

        System.assertEquals(
            6,
            SIAE_UTIL_PricingMdA.calcMesiResidui(String.valueOf(july)),
            'Da luglio a dicembre inclusi devono risultare 6 mesi'
        );

        System.assertEquals(
            0,
            SIAE_UTIL_PricingMdA.calcMesiResidui((String) null),
            'Data null deve restituire 0'
        );

        System.assertEquals(
            0,
            SIAE_UTIL_PricingMdA.calcMesiResidui('data-non-valida'),
            'Data non parsabile deve restituire 0'
        );
    }

    @isTest
    static void testApplyCoeff() {
        Map<String, Object> item = new Map<String, Object>{
            'Amount__c' => 100
        };

        SIAE_UTIL_PricingMdA.applyCoeff(item, 'Amount__c', 1.25);

        System.assertEquals(
            125.00,
            item.get('Amount__c'),
            'Il coefficiente deve essere applicato al valore numerico'
        );

        SIAE_UTIL_PricingMdA.applyCoeff(item, 'CampoInesistente__c', 2);
        SIAE_UTIL_PricingMdA.applyCoeff(null, 'Amount__c', 2);
        SIAE_UTIL_PricingMdA.applyCoeff(item, null, 2);
        SIAE_UTIL_PricingMdA.applyCoeff(item, 'Amount__c', null);
    }

    @isTest
    static void testFlatAmountsWithAdditionalFlatDevices() {
        SIAE_ConfigurazionePricing__c conf = getMockConfig();
        Map<String, Object> sourceItem = getMockFlatSourceItem();

        Map<String, Decimal> result = SIAE_UTIL_PricingMdA.calculateFlatAmounts(
            sourceItem,
            conf,
            12,
            1
        );

        System.assertEquals(150.00, result.get('SIAE_FlatAudio__c'), 'Flat audio deve sommare il Jukebox A-FLAT');
        System.assertEquals(250.00, result.get('SIAE_FlatVideo__c'), 'Flat video deve sommare il Jukebox A-FLAT');

        System.assertEquals(90.00, result.get('SIAE_FlatAudioSemestrale__c'), 'Flat audio semestrale errata');
        System.assertEquals(52.50, result.get('SIAE_FlatAudioTrimestrale__c'), 'Flat audio trimestrale errata');

        System.assertEquals(150.00, result.get('SIAE_FlatVideoSemestrale__c'), 'Flat video semestrale errata');
        System.assertEquals(87.50, result.get('SIAE_FlatVideoTrimestrale__c'), 'Flat video trimestrale errata');
    }

    @isTest
    static void testFlatAmountsAppliesCoeffAreeEsterne() {
        SIAE_ConfigurazionePricing__c conf = getMockConfig();
        Map<String, Object> sourceItem = getMockFlatSourceItem();

        Map<String, Decimal> result = SIAE_UTIL_PricingMdA.calculateFlatAmounts(
            sourceItem,
            conf,
            12,
            1.2
        );

        // (100 base * 1.2) + 50 additional = 170.00 ; (200 base * 1.2) + 50 additional = 290.00
        System.assertEquals(170.00, result.get('SIAE_FlatAudio__c'), 'La maggiorazione aree esterne deve essere applicata alla base flat audio');
        System.assertEquals(290.00, result.get('SIAE_FlatVideo__c'), 'La maggiorazione aree esterne deve essere applicata alla base flat video');

        System.assertEquals(102.00, result.get('SIAE_FlatAudioSemestrale__c'), 'La semestrale deve riflettere la maggiorazione applicata alla base');
        System.assertEquals(59.50, result.get('SIAE_FlatAudioTrimestrale__c'), 'La trimestrale deve riflettere la maggiorazione applicata alla base');

        Map<String, Decimal> resultWithNullCoeff = SIAE_UTIL_PricingMdA.calculateFlatAmounts(
            sourceItem,
            conf,
            12,
            null
        );

        System.assertEquals(150.00, resultWithNullCoeff.get('SIAE_FlatAudio__c'), 'Coefficiente null deve equivalere a nessuna maggiorazione (1.0)');
    }

    @isTest
    static void testFlatAmountsWithInsufficientMonths() {
        SIAE_ConfigurazionePricing__c conf = getMockConfig();
        Map<String, Object> sourceItem = getMockFlatSourceItem();

        Map<String, Decimal> result = SIAE_UTIL_PricingMdA.calculateFlatAmounts(
            sourceItem,
            conf,
            2,
            1
        );

        System.assertEquals(150.00, result.get('SIAE_FlatAudio__c'), 'La flat annuale deve essere calcolata');
        System.assertEquals(0.00, result.get('SIAE_FlatAudioSemestrale__c'), 'Con meno di 6 mesi, semestrale deve essere 0');
        System.assertEquals(0.00, result.get('SIAE_FlatAudioTrimestrale__c'), 'Con meno di 3 mesi, trimestrale deve essere 0');
    }

    @isTest
    static void testFlatAmountsWhenFlatDisabled() {
        SIAE_ConfigurazionePricing__c conf = getMockConfig();
        conf.SIAE_UsaFlat__c = false;

        Map<String, Decimal> result = SIAE_UTIL_PricingMdA.calculateFlatAmounts(
            getMockFlatSourceItem(),
            conf,
            12,
            1
        );

        System.assertEquals(0.00, result.get('SIAE_FlatAudio__c'), 'Flat disabilitata deve restituire 0');
        System.assertEquals(0.00, result.get('SIAE_FlatVideo__c'), 'Flat disabilitata deve restituire 0');
        System.assertEquals(0.00, result.get('SIAE_FlatAudioSemestrale__c'), 'Flat disabilitata deve restituire 0');
        System.assertEquals(0.00, result.get('SIAE_FlatVideoTrimestrale__c'), 'Flat disabilitata deve restituire 0');
    }

    @isTest
    static void testApplyFlatAmountsWritesTarget() {
        SIAE_ConfigurazionePricing__c conf = getMockConfig();

        Map<String, Object> sourceItem = getMockFlatSourceItem();
        Map<String, Object> targetItem = new Map<String, Object>();

        SIAE_UTIL_PricingMdA.applyFlatAmounts(
            sourceItem,
            targetItem,
            conf,
            12,
            1
        );

        System.assertEquals(150.00, targetItem.get('SIAE_FlatAudio__c'), 'Target non aggiornato correttamente per flat audio');
        System.assertEquals(250.00, targetItem.get('SIAE_FlatVideo__c'), 'Target non aggiornato correttamente per flat video');
        System.assertEquals(52.50, targetItem.get('SIAE_FlatAudioTrimestrale__c'), 'Target non aggiornato correttamente per trimestrale audio');
    }

    @isTest
    static void testAdditionalFlatHelpers() {
        SIAE_ConfigurazionePricing__c conf = getMockConfig();
        Map<String, Object> sourceItem = getMockFlatSourceItem();

        System.assertEquals(
            true,
            SIAE_UTIL_PricingMdA.hasAdditionalFlatAttributes(sourceItem, conf),
            'Deve rilevare almeno un attributo A-FLAT valorizzato'
        );

        System.assertEquals(
            50.00,
            SIAE_UTIL_PricingMdA.calculateAdditionalFlatAmount(sourceItem, conf),
            'Deve sommare solo il deviceTotalPrice degli attributi A-FLAT valorizzati'
        );

        Set<String> additionalCodes = SIAE_UTIL_PricingMdA.getAdditionalFlatAttributeCodes(conf);
        System.assertEquals(true, additionalCodes.contains('SIAE-ATTR-JUKEBOX'), 'Codice Jukebox non presente');
        System.assertEquals(true, additionalCodes.contains('SIAE-ATTR-VIDEO-JUKEBOX'), 'Codice Video Jukebox non presente');
        System.assertEquals(true, additionalCodes.contains('SIAE-ATTR-KARAOKE'), 'Codice Karaoke non presente');

        conf.SIAE_AggiungiAFLAT__c = null;
        System.assertEquals(
            false,
            SIAE_UTIL_PricingMdA.hasAdditionalFlatAttributes(sourceItem, conf),
            'Senza configurazione A-FLAT non deve rilevare attributi aggiuntivi'
        );
    }

    @isTest
    static void testExcludedFlatAudioHelpers() {
        SIAE_ConfigurazionePricing__c conf = getMockConfig();
        conf.SIAE_EscludiFlatAudio__c = 'SIAE-ATTR-RADIO';

        Map<String, Object> sourceItem = getMockFlatSourceItem();

        System.assertEquals(
            true,
            SIAE_UTIL_PricingMdA.hasExcludedFlatAudioAttributes(sourceItem, conf),
            'Deve rilevare un attributo che esclude la flat audio'
        );

        Map<String, Decimal> result = SIAE_UTIL_PricingMdA.calculateFlatAmounts(
            sourceItem,
            conf,
            12,
            1
        );

        System.assertEquals(0.00, result.get('SIAE_FlatAudio__c'), 'Flat audio deve essere azzerata');
        System.assertEquals(0.00, result.get('SIAE_FlatAudioSemestrale__c'), 'Flat audio semestrale deve essere azzerata');
        System.assertEquals(0.00, result.get('SIAE_FlatAudioTrimestrale__c'), 'Flat audio trimestrale deve essere azzerata');

        System.assertEquals(250.00, result.get('SIAE_FlatVideo__c'), 'Flat video non deve essere azzerata');

        Set<String> excludedCodes = SIAE_UTIL_PricingMdA.getExcludedFlatAudioAttributeCodes(conf);
        System.assertEquals(true, excludedCodes.contains('SIAE-ATTR-RADIO'), 'Codice esclusione non presente');

        conf.SIAE_EscludiFlatAudio__c = null;
        System.assertEquals(
            false,
            SIAE_UTIL_PricingMdA.hasExcludedFlatAudioAttributes(sourceItem, conf),
            'Senza configurazione di esclusione non deve rilevare esclusioni'
        );
    }

    @isTest
    static void testReadDecimal() {
        Map<String, Object> sourceItem = new Map<String, Object>{
            'Amount1__c' => '123,45',
            'Amount2__c' => '99.99',
            'Amount3__c' => 'abc'
        };

        System.assertEquals(123.45, SIAE_UTIL_PricingMdA.readDecimal(sourceItem, 'Amount1__c'), 'Read decimal con virgola errata');
        System.assertEquals(99.99, SIAE_UTIL_PricingMdA.readDecimal(sourceItem, 'Amount2__c'), 'Read decimal con punto errata');
        System.assertEquals(null, SIAE_UTIL_PricingMdA.readDecimal(sourceItem, 'Amount3__c'), 'Valore non numerico deve restituire null');
        System.assertEquals(null, SIAE_UTIL_PricingMdA.readDecimal(sourceItem, 'Missing__c'), 'Campo assente deve restituire null');
        System.assertEquals(null, SIAE_UTIL_PricingMdA.readDecimal(null, 'Amount1__c'), 'Mappa null deve restituire null');
    }

    @isTest
    static void testCalculateTotalDAForFlatRate() {
        Decimal nonFlat = SIAE_UTIL_PricingMdA.calculateTotalDAForFlatRate(
            100,
            null,
            1.2,
            1.1,
            0.5
        );

        System.assertEquals(100.00, nonFlat, 'Se non c’è flat deve restituire solo baseAmount arrotondato');

        Decimal flatAudio = SIAE_UTIL_PricingMdA.calculateTotalDAForFlatRate(
            384.60,
            'FLAT_AUDIO',
            1.1,
            1.0,
            1.0
        );

        System.assertEquals(423.06, flatAudio, 'Flat audio con maggiorazione MQ errata');

        Decimal flatVideoWithAllCoeffs = SIAE_UTIL_PricingMdA.calculateTotalDAForFlatRate(
            885.75,
            'FLAT_AUDIO_VIDEO',
            1.1,
            1.25,
            0.6
        );

        System.assertEquals(730.74, flatVideoWithAllCoeffs, 'Flat audio-video con coefficienti errata');

        Decimal flatWithNullCoeffs = SIAE_UTIL_PricingMdA.calculateTotalDAForFlatRate(
            100,
            'FLAT_AUDIO',
            null,
            null,
            null
        );

        System.assertEquals(100.00, flatWithNullCoeffs, 'Coefficienti null devono valere 1');
    }

    @isTest
    static void testIsFlatRateSelected() {
        System.assertEquals(false, SIAE_UTIL_PricingMdA.isFlatRateSelected(null), 'Null non deve essere flat');
        System.assertEquals(false, SIAE_UTIL_PricingMdA.isFlatRateSelected(''), 'Stringa vuota non deve essere flat');
        System.assertEquals(true, SIAE_UTIL_PricingMdA.isFlatRateSelected('FLAT_AUDIO'), 'FLAT_AUDIO deve essere flat');
        System.assertEquals(true, SIAE_UTIL_PricingMdA.isFlatRateSelected('FLAT_AUDIO_VIDEO'), 'FLAT_AUDIO_VIDEO deve essere flat');
    }

    @isTest
    static void testNullAndEmptyFlatInputs() {
        SIAE_ConfigurazionePricing__c conf = getMockConfig();

        Map<String, Decimal> resultNullSource = SIAE_UTIL_PricingMdA.calculateFlatAmounts(
            null,
            conf,
            12,
            1
        );

        System.assertEquals(0.00, resultNullSource.get('SIAE_FlatAudio__c'), 'Source null deve restituire 0');

        Map<String, Decimal> resultNullConf = SIAE_UTIL_PricingMdA.calculateFlatAmounts(
            getMockFlatSourceItem(),
            null,
            12,
            1
        );

        System.assertEquals(0.00, resultNullConf.get('SIAE_FlatAudio__c'), 'Conf null deve restituire 0');

        System.assertEquals(
            0.00,
            SIAE_UTIL_PricingMdA.calculateAdditionalFlatAmount(null, conf),
            'Source null deve produrre additional flat 0'
        );

        System.assertEquals(
            0.00,
            SIAE_UTIL_PricingMdA.calculateAdditionalFlatAmount(getMockFlatSourceItem(), null),
            'Conf null deve produrre additional flat 0'
        );
    }

    @isTest
    static void testResolvePicklistValues() {
        System.assertEquals(
            0,
            SIAE_UTIL_PricingMdA.resolvePicklistValues(null).size(),
            'Set nullo deve restituire mappa vuota'
        );
        System.assertEquals(
            0,
            SIAE_UTIL_PricingMdA.resolvePicklistValues(new Set<Id>()).size(),
            'Set vuoto deve restituire mappa vuota'
        );

        AttributePicklist picklist = new AttributePicklist(Name = 'Test Classificazione Util');
        insert picklist;

        AttributePicklistValue pv = new AttributePicklistValue(
            Name = 'Non convenzionata',
            PicklistId = picklist.Id,
            Code = 'NON-CONV-UTIL-TEST',
            Value = 'Non convenzionata'
        );
        insert pv;

        Map<Id, String> resolved = SIAE_UTIL_PricingMdA.resolvePicklistValues(new Set<Id>{ pv.Id });
        System.assertEquals('Non convenzionata', resolved.get(pv.Id), 'Value risolto correttamente');
    }

    @isTest
    static void testResolvePicklistAttributeValues() {
        // Lista nulla/vuota: no-op, nessuna eccezione
        SIAE_UTIL_PricingMdA.resolvePicklistAttributeValues(null);
        SIAE_UTIL_PricingMdA.resolvePicklistAttributeValues(new List<Object>());

        AttributePicklist picklist = new AttributePicklist(Name = 'Test Classificazione Util JSON');
        insert picklist;

        AttributePicklistValue pv = new AttributePicklistValue(
            Name = 'Capelli ed estetica',
            PicklistId = picklist.Id,
            Code = 'CAP-EST-UTIL-TEST',
            Value = 'Capelli ed estetica'
        );
        insert pv;

        Map<String, Object> attrPicklist = new Map<String, Object>{
            'AttributeDefinitionCode' => 'SIAE-ATTR-CLASS',
            'AttributePicklistValue'  => (String) pv.Id
        };
        Map<String, Object> attrNumber = new Map<String, Object>{
            'AttributeDefinitionCode' => 'SIAE-ATTR-QTA',
            'AttributeValue'          => '100'
        };
        Map<String, Object> attrInvalidPicklist = new Map<String, Object>{
            'AttributeDefinitionCode' => 'SIAE-ATTR-FAKE',
            'AttributePicklistValue'  => 'INVALID_ID'
        };

        List<Object> attrList = new List<Object>{ attrPicklist, attrNumber, attrInvalidPicklist };

        Test.startTest();
        SIAE_UTIL_PricingMdA.resolvePicklistAttributeValues(attrList);
        Test.stopTest();

        System.assertEquals(
            'Capelli ed estetica',
            (String) attrPicklist.get('AttributeValue'),
            'Il valore Picklist deve essere risolto e scritto su AttributeValue'
        );
        System.assertEquals(
            '100',
            (String) attrNumber.get('AttributeValue'),
            'Attributo gia testuale non deve essere alterato'
        );
        System.assertEquals(
            null,
            attrInvalidPicklist.get('AttributeValue'),
            'Id picklist non valido deve essere scartato senza eccezioni'
        );
    }
}