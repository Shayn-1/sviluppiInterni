/**
 * @description : End-to-end price validation of the MdA licence catalog.
 *                One @isTest method per row of NRT-PROD.xlsx, sheet "NRT v2" (49 rows):
 *                testCaso_<N> where N is the "#" column of that row, so a failure points
 *                back to a single line of the source file.
 *                Every method builds the scenario of its row with SIAE_UTIL_BuilderValidatorMdA
 *                (product, attributes, dates, coverage, optional commercial agreement and flat
 *                rate), prices it through RevSalesTrxn.PlaceSalesTransactionExecutor and asserts
 *                the five expected amounts of the row on the resulting QuoteLineItem.
 *                Column mapping:
 *                  Codice prodotto      -> SIAE_ProductSelector.byCode
 *                  Configurazione       -> addAttribute, one "<CODE>: <value>" line each,
 *                                          prefixed with SIAE-ATTR-
 *                  Data inizio          -> withStartDate
 *                  Copertura            -> withCoverage; EndDate is derived, the file has no
 *                                          end date column: Annuale = +1 year - 1 day,
 *                                          Semestrale = +6 months - 1 day,
 *                                          Trimestrale = +3 months - 1 day
 *                  Accordo / Flat       -> withCommercialAgreement / withFlatRate (API value)
 *                  Risultato Atteso DDA -> PriceField.TOTAL_DA (first line of the cell only:
 *                                          further lines are GetPriceHeadless comparison notes)
 *                  Risultato Atteso DC  -> PriceField.DIRITTI_CONNESSI
 *                  Sconto AC DDA / DC   -> PriceField.TOTALE_SCONTO_AC_DDA / _DC, which are
 *                                          discount amounts (SIAE_TotalDiscountCADA__c /
 *                                          SIAE_TotalDiscountCADC__c), not the
 *                                          SIAE_*DiscountPercent__c fractions
 *                  Quota AC             -> PriceField.QUOTA_AC
 *                SeeAllData is required: the pricing engine reads real org catalog and rate data
 *                (PricebookEntryDerivedPrice, ContractItemPrice, SIAE_ConfigurazionePricing__c),
 *                which cannot be recreated as test fixtures.
 * @author      : Domenico Del Prete - ddelprete.consulente@siae.it
 **/
@isTest(SeeAllData=true)
public with sharing class SIAE_Pricing_MdA_2026_T {

    private static final String COVERAGE_ANNUALE = 'Annuale';
    private static final String COVERAGE_SEMESTRALE = 'Semestrale';
    private static final String COVERAGE_TRIMESTRALE = 'Trimestrale';

    @isTest
    static void testCaso_1() {
        // albergo 3stelle lc licrist no
        Test.startTest();
        scenario('SIAE-PROD-ALBERGO', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .addAttribute('SIAE-ATTR-CLASS', '3 Stelle')
            .addAttribute('SIAE-ATTR-LIC-RIST', 'NO')
            .addAttribute('SIAE-ATTR-TV-UND40', '1')
            .addAttribute('SIAE-ATTR-ALTOP-TV-UND40', '1')
            .addAttribute('SIAE-ATTR-RADIO', '2')
            .addAttribute('SIAE-ATTR-ALTOP-RADIO', '2')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '666.33')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '121.01')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_2() {
        // albergo 3stelle lc licrist si
        Test.startTest();
        scenario('SIAE-PROD-ALBERGO', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .addAttribute('SIAE-ATTR-CLASS', '3 Stelle')
            .addAttribute('SIAE-ATTR-LIC-RIST', 'SI')
            .addAttribute('SIAE-ATTR-TV-UND40', '1')
            .addAttribute('SIAE-ATTR-ALTOP-TV-UND40', '1')
            .addAttribute('SIAE-ATTR-RADIO', '2')
            .addAttribute('SIAE-ATTR-ALTOP-RADIO', '2')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '713.60')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '121.01')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_3() {
        // albergo 3stelle riconversione automatica
        Test.startTest();
        scenario('SIAE-PROD-ALBERGO', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .addAttribute('SIAE-ATTR-CLASS', '3 Stelle')
            .addAttribute('SIAE-ATTR-RADIO', '0')
            .addAttribute('SIAE-ATTR-RADIO-CAM', '3')
            .addAttribute('SIAE-ATTR-ALTOP-RADIO', '1')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '113.12')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '121.01')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_4() {
        // albergo 4stelle tv qty3 camere
        Test.startTest();
        scenario('SIAE-PROD-ALBERGO', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .addAttribute('SIAE-ATTR-CLASS', '4 Stelle')
            .addAttribute('SIAE-ATTR-TV-UND40', '3')
            .addAttribute('SIAE-ATTR-RADIO', '1')
            .addAttribute('SIAE-ATTR-RADIO-CAM', '15')
            .addAttribute('SIAE-ATTR-TV-UND40-CAM', '1')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '1927.64')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '184.64')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_5() {
        // albergo 5stelle 300camere
        Test.startTest();
        scenario('SIAE-PROD-ALBERGO', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .addAttribute('SIAE-ATTR-CLASS', '5 Stelle')
            .addAttribute('SIAE-ATTR-QTA', '300')
            .addAttribute('SIAE-ATTR-RADIO', '1')
            .addAttribute('SIAE-ATTR-RADIO-CAM', '300')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '749.19')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '502.41')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_6() {
        // albergo 3stelle semestrale
        Test.startTest();
        scenario('SIAE-PROD-ALBERGO', Date.newInstance(2026, 1, 1), COVERAGE_SEMESTRALE)
            .addAttribute('SIAE-ATTR-CLASS', '3 Stelle')
            .addAttribute('SIAE-ATTR-RADIO', '1')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '57.45')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '85.01')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_7() {
        // affitti brevi audio video altop
        Test.startTest();
        scenario('SIAE-PROD-AFFITTI-BREVI', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .addAttribute('SIAE-ATTR-QTA', '5')
            .addAttribute('SIAE-ATTR-AUDIO', '1')
            .addAttribute('SIAE-ATTR-VIDEO', '1')
            .addAttribute('SIAE-ATTR-ALTOP-VIDEO', '1')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '249.40')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '101.99')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_8() {
        // affitti brevi 30 nuova struttura accordo
        Test.startTest();
        scenario('SIAE-PROD-AFFITTI-BREVI', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .withCommercialAgreement('ANBBA')
            .addAttribute('SIAE-ATTR-QTA', '30')
            .addAttribute('SIAE-ATTR-NUOVA-STRU', 'SI')
            .addAttribute('SIAE-ATTR-AUDIO', '1')
            .addAttribute('SIAE-ATTR-ALTOP-AUDIO', '1')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '41.59')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '101.99')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '9.65')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_9() {
        // agriturismi sola radio
        Test.startTest();
        scenario('SIAE-PROD-AGRITURISMI', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .addAttribute('SIAE-ATTR-QTA', '10')
            .addAttribute('SIAE-ATTR-RADIO', '1')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '56.60')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '47.56')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_10() {
        // agriturismi radio tv camere accordo
        Test.startTest();
        scenario('SIAE-PROD-AGRITURISMI', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .withCommercialAgreement('AGRITU')
            .addAttribute('SIAE-ATTR-QTA', '10')
            .addAttribute('SIAE-ATTR-RADIO', '1')
            .addAttribute('SIAE-ATTR-TV-UND40', '1')
            .addAttribute('SIAE-ATTR-RADIO-CAM', '5')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '228.32')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '72.78')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '19.59')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '5.82')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_11() {
        // negozi 180mq radio5 altop5
        Test.startTest();
        scenario('SIAE-PROD-NEGOZI', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .addAttribute('SIAE-ATTR-QTA', '180')
            .addAttribute('SIAE-ATTR-RADIO', '5')
            .addAttribute('SIAE-ATTR-ALTOP-RADIO', '5')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '312.36')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '58.85')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_12() {
        // negozi 250mq tv2 altop3
        Test.startTest();
        scenario('SIAE-PROD-NEGOZI', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .addAttribute('SIAE-ATTR-QTA', '250')
            .addAttribute('SIAE-ATTR-TV-UND40', '2')
            .addAttribute('SIAE-ATTR-ALTOP-TV-UND40', '3')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '1043.05')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '190.04')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_13() {
        // negozi 1200mq radioinstore altop60
        Test.startTest();
        scenario('SIAE-PROD-NEGOZI', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .addAttribute('SIAE-ATTR-QTA', '1200')
            .addAttribute('SIAE-ATTR-RADIOINSTORE', '1')
            .addAttribute('SIAE-ATTR-ALTOP-RADIOINSTORE', '60')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '3211.92')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '442.07')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_14() {
        // negozi 150mq audio2 semestrale
        Test.startTest();
        scenario('SIAE-PROD-NEGOZI', Date.newInstance(2026, 1, 1), COVERAGE_SEMESTRALE)
            .addAttribute('SIAE-ATTR-QTA', '150')
            .addAttribute('SIAE-ATTR-AUDIO', '2')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '171.72')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '49.52')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_15() {
        // negozi 150mq audio2 accordo confco
        Test.startTest();
        scenario('SIAE-PROD-NEGOZI', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .withCommercialAgreement('CONFCO')
            .addAttribute('SIAE-ATTR-QTA', '150')
            .addAttribute('SIAE-ATTR-AUDIO', '2')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '263.70')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '49.52')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '75.92')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '20.79')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '55.42');
        Test.stopTest();
    }

    @isTest
    static void testCaso_16() {
        // acconciatori capelli 80mq impegno1anno
        Test.startTest();
        scenario('SIAE-PROD-ACCONCIATORI', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .addAttribute('SIAE-ATTR-CLASS', 'Capelli ed estetica')
            .addAttribute('SIAE-ATTR-QTA', '80')
            .addAttribute('SIAE-ATTR-IMPEGNO', 'Paga per un anno')
            .addAttribute('SIAE-ATTR-RADIO', '1')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '56.60')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '19.97')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_17() {
        // acconciatori capelli 80mq impegno2anni
        Test.startTest();
        scenario('SIAE-PROD-ACCONCIATORI', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .addAttribute('SIAE-ATTR-CLASS', 'Capelli ed estetica')
            .addAttribute('SIAE-ATTR-QTA', '80')
            .addAttribute('SIAE-ATTR-IMPEGNO', 'Paga per due anni (5% di sconto)')
            .addAttribute('SIAE-ATTR-RADIO', '1')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '56.60')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '19.97')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_18() {
        // acconciatori massaggi 60mq radio tv trimestrale
        Test.startTest();
        scenario('SIAE-PROD-ACCONCIATORI', Date.newInstance(2026, 1, 1), COVERAGE_TRIMESTRALE)
            .addAttribute('SIAE-ATTR-CLASS', 'Altre attivit\u00E0 (Massaggi, Unghie)')
            .addAttribute('SIAE-ATTR-QTA', '60')
            .addAttribute('SIAE-ATTR-RADIO', '1')
            .addAttribute('SIAE-ATTR-TV-UND40', '1')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '92.28')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '12.35')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_19() {
        // bar 60mq no area esterna audio video
        Test.startTest();
        scenario('SIAE-PROD-BAR', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .addAttribute('SIAE-ATTR-QTA', '60')
            .addAttribute('SIAE-ATTR-AREE-EST', 'No')
            .addAttribute('SIAE-ATTR-AUDIO', '1')
            .addAttribute('SIAE-ATTR-VIDEO', '1')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '388.10')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '72.74')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_20() {
        // bar 700mq area esterna oltre50 attese
        Test.startTest();
        scenario('SIAE-PROD-BAR', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .addAttribute('SIAE-ATTR-QTA', '700')
            .addAttribute('SIAE-ATTR-AREE-EST', 'Si, superiori a 50 mq')
            .addAttribute('SIAE-ATTR-VIDEO', '2')
            .addAttribute('SIAE-ATTR-AUDIO', '1')
            .addAttribute('SIAE-ATTR-ATTESE-TEL', '1')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '1831.24')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '379.28')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_21() {
        // bar 100mq flat audio
        Test.startTest();
        scenario('SIAE-PROD-BAR', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .withFlatRate('FLAT_AUDIO')
            .addAttribute('SIAE-ATTR-QTA', '100')
            .addAttribute('SIAE-ATTR-AREE-EST', 'No')
            .addAttribute('SIAE-ATTR-AUDIO', '1')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '244.30')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '75.18')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_22() {
        // bar 100mq flat audio video area fino50
        Test.startTest();
        scenario('SIAE-PROD-BAR', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .withFlatRate('FLAT_AUDIO_VIDEO')
            .addAttribute('SIAE-ATTR-QTA', '100')
            .addAttribute('SIAE-ATTR-AREE-EST', 'Si, fino a 50 mq')
            .addAttribute('SIAE-ATTR-AUDIO', '1')
            .addAttribute('SIAE-ATTR-VIDEO', '1')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '672.24')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '106.69')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_23() {
        // bar 100mq audio ottobre accordo fipe
        Test.startTest();
        scenario('SIAE-PROD-BAR', Date.newInstance(2026, 10, 1), COVERAGE_ANNUALE)
            .withCommercialAgreement('FIPE')
            .addAttribute('SIAE-ATTR-QTA', '100')
            .addAttribute('SIAE-ATTR-AREE-EST', 'No')
            .addAttribute('SIAE-ATTR-AUDIO', '1')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '44.46')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '11.22')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '13.33')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '4.38')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '5.41');
        Test.stopTest();
    }

    @isTest
    static void testCaso_24() {
        // balneari video2 audio accordo fiba
        Test.startTest();
        scenario('SIAE-PROD-BALNEARI', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .withCommercialAgreement('FIBA')
            .addAttribute('SIAE-ATTR-QTA', '1')
            .addAttribute('SIAE-ATTR-VIDEO', '2')
            .addAttribute('SIAE-ATTR-AUDIO', '1')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '528.33')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '89.55')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '176.63')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '22.13')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '47.76');
        Test.stopTest();
    }

    @isTest
    static void testCaso_25() {
        // circoli video radio accordo arci
        Test.startTest();
        scenario('SIAE-PROD-CIRCOLI', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .withCommercialAgreement('ARCI')
            .addAttribute('SIAE-ATTR-QTA', '1')
            .addAttribute('SIAE-ATTR-VIDEO', '1')
            .addAttribute('SIAE-ATTR-RADIO', '1')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '286.55')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '156.43')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '27.43')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_26() {
        // enti ecclesiastici radio audio accordo senza effetto
        Test.startTest();
        scenario('SIAE-PROD-ENTI-ECCLESIASTICI', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .withCommercialAgreement('ARCI')
            .addAttribute('SIAE-ATTR-QTA', '1')
            .addAttribute('SIAE-ATTR-RADIO', '1')
            .addAttribute('SIAE-ATTR-AUDIO', '1')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '63.30')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '40.75')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_27() {
        // terza eta tv audio altop radio camere60
        Test.startTest();
        scenario('SIAE-PROD-TERZA-ETA', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .addAttribute('SIAE-ATTR-TV-UND40', '1')
            .addAttribute('SIAE-ATTR-AUDIO', '2')
            .addAttribute('SIAE-ATTR-ALTOP-AUDIO', '1')
            .addAttribute('SIAE-ATTR-RADIO', '1')
            .addAttribute('SIAE-ATTR-RADIO-CAM', '60')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '349.88')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_28() {
        // terza eta video3 altop accordo anaste
        Test.startTest();
        scenario('SIAE-PROD-TERZA-ETA', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .withCommercialAgreement('ANASTE')
            .addAttribute('SIAE-ATTR-VIDEO', '3')
            .addAttribute('SIAE-ATTR-ALTOP-VIDEO', '1')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '717.56')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_29() {
        // case cura non convenzionata camere accordo aiop
        Test.startTest();
        scenario('SIAE-PROD-CASE-CURA', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .withCommercialAgreement('AIOP')
            .addAttribute('SIAE-ATTR-CLASS', 'Non convenzionata')
            .addAttribute('SIAE-ATTR-VIDEO', '1')
            .addAttribute('SIAE-ATTR-RADIO-CAM', '15')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '554.31')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '47.94')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_30() {
        // campeggi radio camere251
        Test.startTest();
        scenario('SIAE-PROD-CAMPEGGI', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .addAttribute('SIAE-ATTR-QTA', '251')
            .addAttribute('SIAE-ATTR-RADIO', '1')
            .addAttribute('SIAE-ATTR-RADIO-CAM', '251')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '312.97')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_31() {
        // navi traghetto 800pax no cond spe
        Test.startTest();
        scenario('SIAE-PROD-NAVI', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .addAttribute('SIAE-ATTR-CLASS', 'Nave da crociera e da traghetto')
            .addAttribute('SIAE-ATTR-COND-SPE', 'NO')
            .addAttribute('SIAE-ATTR-QTA', '800')
            .addAttribute('SIAE-ATTR-TV-UND40', '2')
            .addAttribute('SIAE-ATTR-ALTOP-TV-UND40', '1')
            .addAttribute('SIAE-ATTR-RADIO', '1')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '1039.25')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_32() {
        // navi traghetto 800pax cond spe si
        Test.startTest();
        scenario('SIAE-PROD-NAVI', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .addAttribute('SIAE-ATTR-CLASS', 'Nave da crociera e da traghetto')
            .addAttribute('SIAE-ATTR-COND-SPE', 'SI')
            .addAttribute('SIAE-ATTR-QTA', '800')
            .addAttribute('SIAE-ATTR-TV-UND40', '2')
            .addAttribute('SIAE-ATTR-ALTOP-TV-UND40', '1')
            .addAttribute('SIAE-ATTR-RADIO', '1')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '395.80')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_33() {
        // lavoro 350dip no uffici pubblici
        Test.startTest();
        scenario('SIAE-PROD-LAVORO', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .addAttribute('SIAE-ATTR-COND-SPE', 'NO')
            .addAttribute('SIAE-ATTR-QTA', '350')
            .addAttribute('SIAE-ATTR-TV-UND40', '1')
            .addAttribute('SIAE-ATTR-RADIO', '1')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '1333.65')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_34() {
        // lavoro 350dip uffici pubblici
        Test.startTest();
        scenario('SIAE-PROD-LAVORO', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .addAttribute('SIAE-ATTR-COND-SPE', 'SI')
            .addAttribute('SIAE-ATTR-QTA', '350')
            .addAttribute('SIAE-ATTR-TV-UND40', '1')
            .addAttribute('SIAE-ATTR-RADIO', '1')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '213.90')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_35() {
        // farmacie 80mq video audio radioinstore accordo
        Test.startTest();
        scenario('SIAE-PROD-FARMACIE', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .withCommercialAgreement('FEDFAR')
            .addAttribute('SIAE-ATTR-QTA', '80')
            .addAttribute('SIAE-ATTR-VIDEO', '1')
            .addAttribute('SIAE-ATTR-AUDIO', '1')
            .addAttribute('SIAE-ATTR-RADIOINSTORE', '1')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '356.69')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '62.42')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_36() {
        // aerei solo a terra
        Test.startTest();
        scenario('SIAE-PROD-AEREI', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .addAttribute('SIAE-ATTR-LUOGO', 'Solo a terra')
            .addAttribute('SIAE-ATTR-QTA', '1')
            .addAttribute('SIAE-ATTR-RADIO', '1')
            .addAttribute('SIAE-ATTR-AUDIO', '1')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '146.33')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_37() {
        // automezzi trasporto passeggeri oltre1500
        Test.startTest();
        scenario('SIAE-PROD-AUTOMEZZI', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .addAttribute('SIAE-ATTR-CLASS', 'Trasporto passeggeri')
            .addAttribute('SIAE-ATTR-CILINDRATA', 'oltre 8 mq / oltre 1.500 cc')
            .addAttribute('SIAE-ATTR-VIDEO', '1')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '361.45')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_38() {
        // palestre piscine oltre25 karaoke video accordo
        Test.startTest();
        scenario('SIAE-PROD-PALESTRE', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .withCommercialAgreement('CIRPAR')
            .addAttribute('SIAE-ATTR-CLASS', 'Piscine oltre 25m, Piste di pattinaggio oltre 60m')
            .addAttribute('SIAE-ATTR-KARAOKE', '1')
            .addAttribute('SIAE-ATTR-VIDEO', '1')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '484.05')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '481.05')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_39() {
        // aeroporti attese25 radio2 altop60
        Test.startTest();
        scenario('SIAE-PROD-AEROPORTI', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .addAttribute('SIAE-ATTR-ATTESE-TEL', '25')
            .addAttribute('SIAE-ATTR-RADIO', '2')
            .addAttribute('SIAE-ATTR-ALTOP-RADIO', '60')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '4067.27')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_40() {
        // bingo compenso unico
        Test.startTest();
        scenario('SIAE-PROD-BINGO', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .addAttribute('SIAE-ATTR-JUKEBOX', '2')
            .addAttribute('SIAE-ATTR-KARAOKE', '1')
            .addAttribute('SIAE-ATTR-VIDEO', '3')
            .addAttribute('SIAE-ATTR-VIDEO-JUKEBOX', '1')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '2174.83')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_41() {
        // banche poste video2
        Test.startTest();
        scenario('SIAE-PROD-BANCHE-POSTE', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .addAttribute('SIAE-ATTR-QTA', '1')
            .addAttribute('SIAE-ATTR-VIDEO', '2')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '970.86')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_42() {
        // rifornimento carburanti tv video
        Test.startTest();
        scenario('SIAE-PROD-RIFORNIMENTO-CARBURANTI', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .addAttribute('SIAE-ATTR-TV-UND40', '1')
            .addAttribute('SIAE-ATTR-VIDEO', '1')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '1214.60')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_43() {
        // stazioni impianti attese video
        Test.startTest();
        scenario('SIAE-PROD-STAZIONI-IMPIANTI', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .addAttribute('SIAE-ATTR-ATTESE-TEL', '1')
            .addAttribute('SIAE-ATTR-VIDEO', '1')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '638.20')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_44() {
        // sale attesa video
        Test.startTest();
        scenario('SIAE-PROD-SALE-ATTESA', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .addAttribute('SIAE-ATTR-VIDEO', '1')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '258.75')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_45() {
        // foyer video
        Test.startTest();
        scenario('SIAE-PROD-FOYER', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .addAttribute('SIAE-ATTR-QTA', '1')
            .addAttribute('SIAE-ATTR-VIDEO', '1')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '512.40')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_46() {
        // comizi tv
        Test.startTest();
        scenario('SIAE-PROD-COMIZI', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .addAttribute('SIAE-ATTR-TV-UND40', '1')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '705.20')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_47() {
        // parcheggi radio
        Test.startTest();
        scenario('SIAE-PROD-PARCHEGGI', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .addAttribute('SIAE-ATTR-RADIO', '1')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '56.60')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_48() {
        // bowling audio
        Test.startTest();
        scenario('SIAE-PROD-BOWLING', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .addAttribute('SIAE-ATTR-AUDIO', '1')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '138.58')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    @isTest
    static void testCaso_49() {
        // ambulanti radio
        Test.startTest();
        scenario('SIAE-PROD-AMBULANTI', Date.newInstance(2026, 1, 1), COVERAGE_ANNUALE)
            .addAttribute('SIAE-ATTR-RADIO', '1')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '56.60')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DDA, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTALE_SCONTO_AC_DC, '0.00')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.QUOTA_AC, '0.00');
        Test.stopTest();
    }

    /**
     * @description Derives the end date of a scenario from its start date and coverage, the
     * source file having no end date column: the covered period ends the day before the
     * anniversary of its start.
     * @param startDate Start date of the covered period.
     * @param coverage Coverage of the row ("Annuale", "Semestrale", "Trimestrale").
     * @return The derived end date.
     */
    private static Date endDateOf(Date startDate, String coverage) {
        if (COVERAGE_ANNUALE.equals(coverage)) {
            return startDate.addYears(1).addDays(-1);
        }
        if (COVERAGE_SEMESTRALE.equals(coverage)) {
            return startDate.addMonths(6).addDays(-1);
        }
        if (COVERAGE_TRIMESTRALE.equals(coverage)) {
            return startDate.addMonths(3).addDays(-1);
        }
        throw new SIAE_UTIL_BuilderValidatorMdA.BuilderValidatorException(
            'Copertura non riconosciuta: ' + coverage + '.'
        );
    }

    /**
     * @description Builds the scenario of one row of the source file, with the end date derived
     * from start date and coverage.
     * @param productCode Value of the "Codice prodotto" column.
     * @param startDate Value of the "Data inizio" column.
     * @param coverage Value of the "Copertura" column.
     * @return The configured builder, ready for further attributes and assertions.
     */
    private static SIAE_UTIL_BuilderValidatorMdA scenario(String productCode, Date startDate, String coverage) {
        Product2 product = SIAE_UTIL_BuilderValidatorMdA.byCode(productCode);
        if (product == null) {
            throw new SIAE_UTIL_BuilderValidatorMdA.BuilderValidatorException('Prodotto non trovato: ' + productCode);
        }
        return new SIAE_UTIL_BuilderValidatorMdA()
            .addProductById(product.Id)
            .withStartDate(startDate)
            .withEndDate(endDateOf(startDate, coverage))
            .withCoverage(coverage);
    }
}