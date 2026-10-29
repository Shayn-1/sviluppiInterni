/**
 * @description : Test class for SIAE_UTIL_BuilderValidatorMdA.
 *                SeeAllData is required: the pricing engine reads real org catalog and
 *                rate data (PricebookEntryDerivedPrice, ContractItemPrice, SIAE_ConfigurazionePricing__c),
 *                which cannot be recreated as test fixtures.
 *                The two priced scenarios reproduce real rows of NRT-PROD.xlsx (sheet "NRT v2"):
 *                Excel row 10 (case #09) and Excel row 7 (case #06). Expected values are the ones
 *                observed running this class against SIAE_DEV, not the "Risultato Atteso" column of
 *                the file, which is the target of Task 05.
 * @author      : Domenico Del Prete - ddelprete.consulente@siae.it
 **/
@isTest(SeeAllData=true)
private class SIAE_UTIL_BuilderValidatorMdA_T {

    private static final String PRODUCT_CODE_AGRITURISMI = 'SIAE-PROD-AGRITURISMI';
    private static final String PRODUCT_CODE_ALBERGO = 'SIAE-PROD-ALBERGO';

    @isTest
    static void testAssertPrice_ScenarioAgriturismiConAttributoLibero() {
        Test.startTest();
        agriturismiScenario()
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '56.60')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '47.56');
        Test.stopTest();
    }

    @isTest
    static void testAssertPrice_ScenarioAlbergoConAttributoPicklist() {
        Test.startTest();
        albergoScenario()
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '57.45')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '85.01');
        Test.stopTest();
    }

    @isTest
    static void testAssertPrice_RiusaLaTransazioneGiaEseguita() {
        SIAE_UTIL_BuilderValidatorMdA builder = agriturismiScenario();

        Test.startTest();
        builder.assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '56.60');
        Integer queriesAfterFirstAssert = Limits.getQueries();
        builder
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '56.60')
            .assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.DIRITTI_CONNESSI, '47.56');
        // Limits are read before stopTest: stopTest restores the counters of the outer context.
        Integer queriesAfterLastAssert = Limits.getQueries();
        Test.stopTest();

        System.assertEquals(
            queriesAfterFirstAssert,
            queriesAfterLastAssert,
            'Le assert successive alla prima devono riusare il QuoteLineItem gia recuperato.'
        );
    }

    @isTest
    static void testAssertPrice_FallisceQuandoLaTransazioneNonRiesce() {
        SIAE_UTIL_BuilderValidatorMdA builder = new SIAE_UTIL_BuilderValidatorMdA()
            .withStartDate(Date.newInstance(2026, 1, 1))
            .withEndDate(Date.newInstance(2026, 12, 31))
            .withCoverage('Annuale');

        Test.startTest();
        String exceptionMessage = null;
        try {
            builder.assertPrice(SIAE_UTIL_BuilderValidatorMdA.PriceField.TOTAL_DA, '48');
        } catch (SIAE_UTIL_BuilderValidatorMdA.BuilderValidatorException e) {
            exceptionMessage = e.getMessage();
        }
        Test.stopTest();

        System.assertNotEquals(
            null,
            exceptionMessage,
            'Una transazione non riuscita deve fallire con BuilderValidatorException.'
        );
        System.assert(
            exceptionMessage.contains('salesTransactionId'),
            'Il messaggio deve riportare il salesTransactionId per la diagnosi: ' + exceptionMessage
        );
    }

    @isTest
    static void testWithFlatRate_AccettaIValoriApiDellaPicklist() {
        SIAE_UTIL_BuilderValidatorMdA builder = new SIAE_UTIL_BuilderValidatorMdA();

        String exceptionMessage = null;
        try {
            builder.withFlatRate('FLAT_AUDIO').withFlatRate('FLAT_AUDIO_VIDEO');
        } catch (SIAE_UTIL_BuilderValidatorMdA.BuilderValidatorException e) {
            exceptionMessage = e.getMessage();
        }

        System.assertEquals(
            null,
            exceptionMessage,
            'I valori API della picklist SIAE_TypeOfFlatRate__c devono essere accettati.'
        );
    }

    @isTest
    static void testWithFlatRate_RifiutaLaLabelDellaPicklist() {
        SIAE_UTIL_BuilderValidatorMdA builder = new SIAE_UTIL_BuilderValidatorMdA();

        Boolean exceptionThrown = false;
        try {
            builder.withFlatRate('FLAT AUDIO');
        } catch (SIAE_UTIL_BuilderValidatorMdA.BuilderValidatorException e) {
            exceptionThrown = true;
        }

        System.assert(
            exceptionThrown,
            'La label "FLAT AUDIO" non e il valore API della picklist e deve essere rifiutata.'
        );
    }

    /**
     * @description Scenario of NRT-PROD.xlsx row 10 (case #09, "agriturismi sola radio"):
     * free-value attributes only, no commercial agreement, no flat rate.
     * Coverage "Annuale" => EndDate = StartDate + 1 anno - 1 giorno.
     * @return The configured builder.
     */
    private static SIAE_UTIL_BuilderValidatorMdA agriturismiScenario() {
        return new SIAE_UTIL_BuilderValidatorMdA()
            .addProductById(SIAE_UTIL_BuilderValidatorMdA.byCode(PRODUCT_CODE_AGRITURISMI).Id)
            .withStartDate(Date.newInstance(2026, 1, 1))
            .withEndDate(Date.newInstance(2026, 12, 31))
            .withCoverage('Annuale')
            .addAttribute('SIAE-ATTR-QTA', '10')
            .addAttribute('SIAE-ATTR-RADIO', '1');
    }

    /**
     * @description Scenario of NRT-PROD.xlsx row 7 (case #06, "albergo 3stelle semestrale"):
     * picklist attribute CLASS plus a free-value attribute.
     * Coverage "Semestrale" => EndDate = StartDate + 6 mesi - 1 giorno.
     * @return The configured builder.
     */
    private static SIAE_UTIL_BuilderValidatorMdA albergoScenario() {
        return new SIAE_UTIL_BuilderValidatorMdA()
            .addProductById(SIAE_UTIL_BuilderValidatorMdA.byCode(PRODUCT_CODE_ALBERGO).Id)
            .withStartDate(Date.newInstance(2026, 1, 1))
            .withEndDate(Date.newInstance(2026, 6, 30))
            .withCoverage('Semestrale')
            .addAttribute('SIAE-ATTR-CLASS', '3 Stelle')
            .addAttribute('SIAE-ATTR-RADIO', '1');
    }
}