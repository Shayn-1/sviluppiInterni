@IsTest
private class SIAE_UTIL_CalculateCommercialQuote_T {

    private static String valueForField(Schema.SObjectField fieldToken, String preferredValue) {
        Schema.DescribeFieldResult dfr = fieldToken.getDescribe();

        if (dfr.getType() == Schema.DisplayType.Picklist || dfr.getType() == Schema.DisplayType.MultiPicklist) {
            for (Schema.PicklistEntry entry : dfr.getPicklistValues()) {
                if (
                    entry != null &&
                    entry.isActive() &&
                    String.isNotBlank(entry.getValue()) &&
                    entry.getValue() == preferredValue
                ) {
                    return entry.getValue();
                }
            }

            for (Schema.PicklistEntry entry : dfr.getPicklistValues()) {
                if (
                    entry != null &&
                    entry.isActive() &&
                    String.isNotBlank(entry.getValue())
                ) {
                    return entry.getValue();
                }
            }

            return null;
        }

        return preferredValue;
    }

    private static SIAE_AccordoCommerciale__c buildAgreement(
        String commercialCode,
        String intersectionCode
    ) {
        SIAE_AccordoCommerciale__c agreement = new SIAE_AccordoCommerciale__c();

        agreement.SIAE_CodiceAccordoCommerciale__c = valueForField(
            SIAE_AccordoCommerciale__c.SIAE_CodiceAccordoCommerciale__c,
            commercialCode
        );

        agreement.SIAE_CodiceDiIncrocio__c = valueForField(
            SIAE_AccordoCommerciale__c.SIAE_CodiceDiIncrocio__c,
            intersectionCode
        );

        return agreement;
    }

    private static Map<String, SIAE_AccordoCommerciale__c> mapForAgreement(
        SIAE_AccordoCommerciale__c agreement
    ) {
        String key =
            agreement.SIAE_CodiceAccordoCommerciale__c +
            '|' +
            agreement.SIAE_CodiceDiIncrocio__c;

        return new Map<String, SIAE_AccordoCommerciale__c>{
            key => agreement
        };
    }

    @IsTest
    static void calculateAccordoCommerciale_quotaUnitaria_withRiduzione() {
        SIAE_AccordoCommerciale__c agreement = buildAgreement(
            'ACCORDO_QUOTA_UNITARIA',
            'FAM_QUOTA_UNITARIA'
        );

        agreement.SIAE_RiduzioneCompensoBase__c = 0.10;
        agreement.SIAE_VoceQuota__c = 'QA001';
        agreement.SIAE_QuotaUnitaria__c = 5;
        agreement.SIAE_PercentualeScontoDC__c = 0.20;

        Map<String, SIAE_AccordoCommerciale__c> agreements = mapForAgreement(agreement);
        String key = agreement.SIAE_CodiceAccordoCommerciale__c + '|' + agreement.SIAE_CodiceDiIncrocio__c;

        Test.startTest();
        SIAE_UTIL_CalculateCommercialQuote.CalculationResult result =
            SIAE_UTIL_CalculateCommercialQuote.calculateAccordoCommerciale(
                key,
                agreements,
                3,
                100
            );
        Test.stopTest();

        System.assertEquals(agreement.Id, result.accordoId, 'AccordoId deve essere copiato dal record.');
        System.assertEquals(agreement.SIAE_CodiceAccordoCommerciale__c, result.codiceAccordoCommerciale);
        System.assertEquals(agreement.SIAE_CodiceDiIncrocio__c, result.codiceIncrocio);
        System.assertEquals(100, result.compensoTotaleInput);
        System.assertEquals(0.10, result.riduzioneCompensoBasePercent);
        System.assertEquals(90, result.compensoTotaleScontato);
        System.assertEquals('QA001', result.voceQuota);
        System.assertEquals(5, result.quotaUnitaria);
        System.assertEquals(15, result.quotaUnitariaTotale);
        System.assertEquals(15, result.quota);
        System.assertEquals('QUOTA_UNITARIA', result.logicaApplicata);
        System.assertEquals(0.20, result.percentualeScontoDC);
    }

    @IsTest
    static void calculateAccordoCommerciale_quotaSuNettoDda_withoutMinimum() {
        SIAE_AccordoCommerciale__c agreement = buildAgreement(
            'ACCORDO_PCT',
            'FAM_PCT'
        );

        agreement.SIAE_RiduzioneCompensoBase__c = 0.25;
        agreement.SIAE_VoceQuota__c = 'QA002';
        agreement.SIAE_PercentualeQuotaSuNettoDDA__c = 0.10;

        Map<String, SIAE_AccordoCommerciale__c> agreements = mapForAgreement(agreement);
        String key = agreement.SIAE_CodiceAccordoCommerciale__c + '|' + agreement.SIAE_CodiceDiIncrocio__c;

        SIAE_UTIL_CalculateCommercialQuote.CalculationResult result =
            SIAE_UTIL_CalculateCommercialQuote.calculateAccordoCommerciale(
                key,
                agreements,
                2,
                200
            );

        System.assertEquals(150, result.compensoTotaleScontato);
        System.assertEquals(0.10, result.percentualeQuotaSuNettoDDA);
        System.assertEquals(15, result.quotaSuNettoDDAValue);
        System.assertEquals(15, result.quota);
        System.assertEquals('QUOTA_SU_NETTO_DDA', result.logicaApplicata);
    }

    @IsTest
    static void calculateAccordoCommerciale_quotaSuNettoDda_withMinimum_takesMinimum() {
        SIAE_AccordoCommerciale__c agreement = buildAgreement(
            'ACCORDO_MINIMO',
            'FAM_MINIMO'
        );

        agreement.SIAE_RiduzioneCompensoBase__c = 0;
        agreement.SIAE_VoceQuota__c = 'QA003';
        agreement.SIAE_PercentualeQuotaSuNettoDDA__c = 0.10;
        agreement.SIAE_MinimoQuota__c = 8;

        Map<String, SIAE_AccordoCommerciale__c> agreements = mapForAgreement(agreement);
        String key = agreement.SIAE_CodiceAccordoCommerciale__c + '|' + agreement.SIAE_CodiceDiIncrocio__c;

        SIAE_UTIL_CalculateCommercialQuote.CalculationResult result =
            SIAE_UTIL_CalculateCommercialQuote.calculateAccordoCommerciale(
                key,
                agreements,
                3,
                100
            );

        System.assertEquals(100, result.compensoTotaleScontato);
        System.assertEquals(10, result.quotaSuNettoDDAValue);
        System.assertEquals(8, result.minimoQuota);
        System.assertEquals(24, result.minimoQuotaTotale);
        System.assertEquals(24, result.quota);
        System.assertEquals('QUOTA_SU_NETTO_DDA_CON_MINIMO', result.logicaApplicata);
    }

    @IsTest
    static void calculateAccordoCommerciale_quotaSuNettoDda_withMinimum_takesPercentage() {
        SIAE_AccordoCommerciale__c agreement = buildAgreement(
            'ACCORDO_MINIMO_BASSO',
            'FAM_MINIMO_BASSO'
        );

        agreement.SIAE_RiduzioneCompensoBase__c = 0;
        agreement.SIAE_VoceQuota__c = 'QA004';
        agreement.SIAE_PercentualeQuotaSuNettoDDA__c = 0.20;
        agreement.SIAE_MinimoQuota__c = 5;

        Map<String, SIAE_AccordoCommerciale__c> agreements = mapForAgreement(agreement);
        String key = agreement.SIAE_CodiceAccordoCommerciale__c + '|' + agreement.SIAE_CodiceDiIncrocio__c;

        SIAE_UTIL_CalculateCommercialQuote.CalculationResult result =
            SIAE_UTIL_CalculateCommercialQuote.calculateAccordoCommerciale(
                key,
                agreements,
                2,
                100
            );

        System.assertEquals(20, result.quotaSuNettoDDAValue);
        System.assertEquals(10, result.minimoQuotaTotale);
        System.assertEquals(20, result.quota);
        System.assertEquals('QUOTA_SU_NETTO_DDA_CON_MINIMO', result.logicaApplicata);
    }

    @IsTest
    static void calculateAccordoCommerciale_voceQuotaWithoutValues() {
        SIAE_AccordoCommerciale__c agreement = buildAgreement(
            'ACCORDO_NO_VALUES',
            'FAM_NO_VALUES'
        );

        agreement.SIAE_VoceQuota__c = 'QA005';

        Map<String, SIAE_AccordoCommerciale__c> agreements = mapForAgreement(agreement);
        String key = agreement.SIAE_CodiceAccordoCommerciale__c + '|' + agreement.SIAE_CodiceDiIncrocio__c;

        SIAE_UTIL_CalculateCommercialQuote.CalculationResult result =
            SIAE_UTIL_CalculateCommercialQuote.calculateAccordoCommerciale(
                key,
                agreements,
                1,
                100
            );

        System.assertEquals(100, result.compensoTotaleScontato);
        System.assertEquals('QA005', result.voceQuota);
        System.assertEquals(null, result.quota);
        System.assertEquals('VOCE_QUOTA_PRESENTE_MA_NESSUN_VALORE_ASSOCIATO', result.logicaApplicata);
    }

    @IsTest
    static void calculateAccordoCommerciale_noVoceQuota() {
        SIAE_AccordoCommerciale__c agreement = buildAgreement(
            'ACCORDO_NO_QUOTA',
            'FAM_NO_QUOTA'
        );

        agreement.SIAE_RiduzioneCompensoBase__c = null;
        agreement.SIAE_VoceQuota__c = null;

        Map<String, SIAE_AccordoCommerciale__c> agreements = mapForAgreement(agreement);
        String key = agreement.SIAE_CodiceAccordoCommerciale__c + '|' + agreement.SIAE_CodiceDiIncrocio__c;

        SIAE_UTIL_CalculateCommercialQuote.CalculationResult result =
            SIAE_UTIL_CalculateCommercialQuote.calculateAccordoCommerciale(
                key,
                agreements,
                1,
                100
            );

        System.assertEquals(100, result.compensoTotaleScontato);
        System.assertEquals(null, result.voceQuota);
        System.assertEquals(null, result.quota);
        System.assertEquals('NESSUNA_VOCE_QUOTA', result.logicaApplicata);
    }

    @IsTest
    static void calculateAccordoCommerciale_missingAgreement_returnsEmptyResult() {
        SIAE_UTIL_CalculateCommercialQuote.CalculationResult result =
            SIAE_UTIL_CalculateCommercialQuote.calculateAccordoCommerciale(
                'MISSING|KEY',
                new Map<String, SIAE_AccordoCommerciale__c>(),
                1,
                100
            );

        System.assertNotEquals(null, result, 'Se la mappa è vuota deve comunque essere restituito un risultato.');
        System.assertEquals(null, result.accordoId, 'Se la mappa è vuota non deve essere valorizzato alcun accordo.');
        System.assertEquals(null, result.logicaApplicata, 'Se la mappa è vuota non deve essere applicata alcuna logica.');
    }

    @IsTest
    static void calculateAccordoCommerciale_keyNotFound_returnsEmptyResult() {
        SIAE_AccordoCommerciale__c agreement = buildAgreement(
            'ACCORDO_PRESENTE',
            'FAM_PRESENTE'
        );

        SIAE_UTIL_CalculateCommercialQuote.CalculationResult result =
            SIAE_UTIL_CalculateCommercialQuote.calculateAccordoCommerciale(
                'OTHER|KEY',
                mapForAgreement(agreement),
                1,
                100
            );

        System.assertNotEquals(null, result, 'Se la chiave non è presente deve comunque essere restituito un risultato.');
        System.assertEquals(null, result.accordoId, 'Se la chiave non è presente non deve essere valorizzato alcun accordo.');
        System.assertEquals(null, result.logicaApplicata, 'Se la chiave non è presente non deve essere applicata alcuna logica.');
    }

    @IsTest
    static void getMapCommercialAgreement_returnsExpectedKey() {
        SIAE_AccordoCommerciale__c agreement = buildAgreement(
            'ACCORDO_QUERY',
            'FAM_QUERY'
        );

        agreement.SIAE_RiduzioneCompensoBase__c = 0.05;
        agreement.SIAE_VoceQuota__c = 'QA_QUERY';
        agreement.SIAE_QuotaUnitaria__c = 2;

        insert agreement;

        Set<String> commercialCodes = new Set<String>{
            agreement.SIAE_CodiceAccordoCommerciale__c
        };

        Set<String> productFamilies = new Set<String>{
            agreement.SIAE_CodiceDiIncrocio__c
        };

        Test.startTest();
        Map<String, SIAE_AccordoCommerciale__c> result =
            SIAE_UTIL_CalculateCommercialQuote.getMapCommercialAgreement(
                commercialCodes,
                productFamilies
            );
        Test.stopTest();

        String expectedKey =
            agreement.SIAE_CodiceAccordoCommerciale__c +
            '|' +
            agreement.SIAE_CodiceDiIncrocio__c;

        System.assertEquals(true, result.containsKey(expectedKey), 'La mappa deve contenere la chiave codiceAccordo|codiceIncrocio.');
        System.assertEquals(agreement.Id, result.get(expectedKey).Id, 'La mappa deve restituire il record inserito.');
    }

    @IsTest
    static void getMapCommercialAgreement_emptyInputs_returnsEmptyMap() {
        Map<String, SIAE_AccordoCommerciale__c> result =
            SIAE_UTIL_CalculateCommercialQuote.getMapCommercialAgreement(
                new Set<String>(),
                new Set<String>()
            );

        System.assertEquals(0, result.size(), 'Con input vuoti non deve tornare alcun accordo.');
    }
    @IsTest
    static void commercialAgreementIndex_resolvesByEffectiveDate() {
        SIAE_AccordoCommerciale__c agreement2026 = buildAgreement('ACCORDO_DATE', 'FAM_DATE');
        agreement2026.SIAE_DataInizioValidita__c = Datetime.newInstanceGMT(2026, 1, 1, 0, 0, 0);
        agreement2026.SIAE_DataFineValidita__c = Datetime.newInstanceGMT(2026, 12, 31, 23, 59, 59);
        agreement2026.SIAE_RiduzioneCompensoBase__c = 0.10;

        SIAE_AccordoCommerciale__c agreement2027 = buildAgreement('ACCORDO_DATE', 'FAM_DATE');
        agreement2027.SIAE_DataInizioValidita__c = Datetime.newInstanceGMT(2027, 1, 1, 0, 0, 0);
        agreement2027.SIAE_DataFineValidita__c = Datetime.newInstanceGMT(2027, 12, 31, 23, 59, 59);
        agreement2027.SIAE_RiduzioneCompensoBase__c = 0.20;

        SIAE_UTIL_CalculateCommercialQuote.CommercialAgreementIndex index =
            new SIAE_UTIL_CalculateCommercialQuote.CommercialAgreementIndex();
        index.add(agreement2026);
        index.add(agreement2027);

        String key = agreement2026.SIAE_CodiceAccordoCommerciale__c + '|' + agreement2026.SIAE_CodiceDiIncrocio__c;

        System.assertEquals(
            0.10,
            index.resolve(key, Date.newInstance(2026, 12, 31)).SIAE_RiduzioneCompensoBase__c
        );
        System.assertEquals(
            0.20,
            index.resolve(key, Date.newInstance(2027, 1, 1)).SIAE_RiduzioneCompensoBase__c
        );
        System.assertEquals(null, index.resolve(key, Date.newInstance(2028, 1, 1)));
    }

}