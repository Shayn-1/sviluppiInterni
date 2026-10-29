/**
 * @description       Test class for SIAE_UTIL_GenereLocaleConfig
 * @author            Gaetano Iuliano - gaetano.iuliano@nttdata.com
 * @group             NTT Data — SIAE
 * @createdDate       2026-06-15
 * @lastModifiedDate  2026-06-15
 * @lastModifiedBy    Gaetano Iuliano
 */
@isTest
private class SIAE_UTIL_GenereLocaleConfig_T {

    // CMT SIAE_GenereLocale.G02_Sala: GenereName='Sala', ProductCode='SIAE-PROD-FOYER', GenereCode='02'
    private static final String GENERE_SALA         = 'Sala';
    private static final String PROD_SALA           = 'SIAE-PROD-FOYER';
    private static final String CODICE_SALA         = '02';

    // resolveTipoAutomezzo constants (mirrors private constants in the class under test)
    private static final String TIPO_TRASPORTO      = 'Trasporto passeggeri';
    private static final String TIPO_AMBULANTE_SI   = 'Adibito al dettaglio ambulante';
    private static final String TIPO_AMBULANTE_NO   = 'Non adibito al dettaglio ambulante (fiere, propaganda)';
    private static final String CIL_FINO            = 'fino a 8 mq / fino a 1.500 cc';
    private static final String CIL_OLTRE           = 'oltre 8 mq / oltre 1.500 cc';

    // resolveUtilizzoNave constants
    private static final String NAVE_COSTIERA       = 'Nave adibita a navigazione interna da costiera';
    private static final String NAVE_TRAGHETTO      = 'Nave da crociera e da traghetto';

    // ────────────────────────────────────────────────────
    // load()
    // ────────────────────────────────────────────────────

    @isTest
    static void testLoad_ValidCombo() {
        Test.startTest();
        SIAE_UTIL_GenereLocaleConfig.GenereConfig cfg =
            SIAE_UTIL_GenereLocaleConfig.load(GENERE_SALA, PROD_SALA);
        Test.stopTest();

        System.assertNotEquals(null, cfg, 'Config must not be null');
        System.assertEquals(CODICE_SALA, cfg.codiceGenere, 'CodiceGenere must be 02');
        System.assertNotEquals(null, cfg.localeParams);
        System.assertNotEquals(null, cfg.spazioParams);
        System.assertNotEquals(null, cfg.schedaParams);
    }

    @isTest
    static void testLoad_Cache_ReturnsSameInstance() {
        // Two calls with same key → second hit comes from cache (no exception, same codice)
        SIAE_UTIL_GenereLocaleConfig.GenereConfig cfg1 =
            SIAE_UTIL_GenereLocaleConfig.load(GENERE_SALA, PROD_SALA);
        SIAE_UTIL_GenereLocaleConfig.GenereConfig cfg2 =
            SIAE_UTIL_GenereLocaleConfig.load(GENERE_SALA, PROD_SALA);

        System.assertEquals(cfg1.codiceGenere, cfg2.codiceGenere, 'Cached config must match');
        // Same instance from cache: Apex == on custom class without equals() checks reference identity
        System.assert(cfg1 == cfg2, 'Must return same instance from cache');
    }

    @isTest
    static void testLoad_UnknownCombo_ThrowsException() {
        Test.startTest();
        try {
            SIAE_UTIL_GenereLocaleConfig.load('GenereInesistente', 'PROD-XXX');
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('GenereInesistente'), 'Error must mention genere name');
        }
        Test.stopTest();
    }

    @isTest
    static void testLoad_SpazioParams_Populated() {
        // G93 Pub/Birreria/Disco Pub has SIAE_GenereLocaleParameter with SPAZIO scope
        SIAE_UTIL_GenereLocaleConfig.GenereConfig cfg =
            SIAE_UTIL_GenereLocaleConfig.load('Pub/Birreria/Disco Pub', 'SIAE-PROD-BAR');

        System.assertEquals('93', cfg.codiceGenere, 'CodiceGenere must be 93');
        System.assert(cfg.spazioParams.size() > 0, 'G93 must have at least 1 SPAZIO param');
        SIAE_GenereLocaleParameter__mdt first = cfg.spazioParams[0];
        System.assertEquals(SIAE_UTIL_GenereLocaleConfig.SCOPE_SPAZIO, first.SIAE_Scope__c);
    }

    @isTest
    static void testLoad_LocaleParams_Populated() {
        // G02 has SIAE_GenereLocaleParameter.G02_LOCALE_capienza → localeParams not empty
        SIAE_UTIL_GenereLocaleConfig.GenereConfig cfg =
            SIAE_UTIL_GenereLocaleConfig.load(GENERE_SALA, PROD_SALA);

        System.assert(cfg.localeParams.size() > 0, 'G02 must have at least 1 LOCALE param');
        SIAE_GenereLocaleParameter__mdt first = cfg.localeParams[0];
        System.assertEquals(CODICE_SALA, first.SIAE_GenereCode__c);
        System.assertEquals(SIAE_UTIL_GenereLocaleConfig.SCOPE_LOCALE, first.SIAE_Scope__c);
    }

    // ────────────────────────────────────────────────────
    // getGenereCode()
    // ────────────────────────────────────────────────────

    @isTest
    static void testGetGenereCode_BlankName_ThrowsException() {
        try {
            SIAE_UTIL_GenereLocaleConfig.getGenereCode('', PROD_SALA);
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('valorizzati'), 'Error must mention required args');
        }
    }

    @isTest
    static void testGetGenereCode_BlankProductCode_ThrowsException() {
        try {
            SIAE_UTIL_GenereLocaleConfig.getGenereCode(GENERE_SALA, null);
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('valorizzati'));
        }
    }

    @isTest
    static void testGetGenereCode_NotFound_ThrowsException() {
        try {
            SIAE_UTIL_GenereLocaleConfig.getGenereCode('XXXXXX', 'PROD-XXXXXX');
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('Nessun mapping'));
        }
    }

    @isTest
    static void testGetGenereCode_Valid() {
        String codice = SIAE_UTIL_GenereLocaleConfig.getGenereCode(GENERE_SALA, PROD_SALA);
        System.assertEquals(CODICE_SALA, codice);
    }

    // ────────────────────────────────────────────────────
    // getParameters()
    // ────────────────────────────────────────────────────

    @isTest
    static void testGetParameters_BlankGenereCode_ThrowsException() {
        try {
            SIAE_UTIL_GenereLocaleConfig.getParameters('', SIAE_UTIL_GenereLocaleConfig.SCOPE_LOCALE);
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('richiesti'));
        }
    }

    @isTest
    static void testGetParameters_BlankScope_ThrowsException() {
        try {
            SIAE_UTIL_GenereLocaleConfig.getParameters(CODICE_SALA, null);
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('richiesti'));
        }
    }

    @isTest
    static void testGetParameters_Locale_ReturnsResults() {
        List<SIAE_GenereLocaleParameter__mdt> params =
            SIAE_UTIL_GenereLocaleConfig.getParameters(CODICE_SALA, SIAE_UTIL_GenereLocaleConfig.SCOPE_LOCALE);

        System.assertNotEquals(null, params);
        System.assert(params.size() > 0, 'G02 must have LOCALE params');
        for (SIAE_GenereLocaleParameter__mdt p : params) {
            System.assertEquals(CODICE_SALA, p.SIAE_GenereCode__c);
            System.assertEquals(SIAE_UTIL_GenereLocaleConfig.SCOPE_LOCALE, p.SIAE_Scope__c);
        }
    }

    @isTest
    static void testGetParameters_Spazio_IncludesLocaleForG02() {
        // Regola v1.1: ogni parametro LOCALE deve esistere anche a scope SPAZIO (spazio superset di locale)
        List<SIAE_GenereLocaleParameter__mdt> localeParams =
            SIAE_UTIL_GenereLocaleConfig.getParameters(CODICE_SALA, SIAE_UTIL_GenereLocaleConfig.SCOPE_LOCALE);
        List<SIAE_GenereLocaleParameter__mdt> spazioParams =
            SIAE_UTIL_GenereLocaleConfig.getParameters(CODICE_SALA, SIAE_UTIL_GenereLocaleConfig.SCOPE_SPAZIO);

        System.assertNotEquals(null, spazioParams);
        System.assert(!localeParams.isEmpty(), 'G02 deve avere almeno un parametro LOCALE');

        Set<String> spazioNames = new Set<String>();
        for (SIAE_GenereLocaleParameter__mdt p : spazioParams) {
            spazioNames.add(p.SIAE_ParameterName__c);
        }
        for (SIAE_GenereLocaleParameter__mdt p : localeParams) {
            System.assert(
                spazioNames.contains(p.SIAE_ParameterName__c),
                'Parametro LOCALE ' + p.SIAE_ParameterName__c + ' deve esistere anche a SPAZIO per G02'
            );
        }
    }

    @isTest
    static void testGetParameters_Unknown_ReturnsEmpty() {
        List<SIAE_GenereLocaleParameter__mdt> params =
            SIAE_UTIL_GenereLocaleConfig.getParameters('XX', SIAE_UTIL_GenereLocaleConfig.SCOPE_LOCALE);

        System.assertNotEquals(null, params);
        System.assertEquals(0, params.size());
    }

    // ────────────────────────────────────────────────────
    // parseValueMap()
    // ────────────────────────────────────────────────────

    @isTest
    static void testParseValueMap_Null() {
        Map<String, String> result = SIAE_UTIL_GenereLocaleConfig.parseValueMap(null);
        System.assertNotEquals(null, result);
        System.assertEquals(0, result.size());
    }

    @isTest
    static void testParseValueMap_Blank() {
        Map<String, String> result = SIAE_UTIL_GenereLocaleConfig.parseValueMap('   ');
        System.assertEquals(0, result.size());
    }

    @isTest
    static void testParseValueMap_Valid() {
        Map<String, String> result = SIAE_UTIL_GenereLocaleConfig.parseValueMap('A=>1;B=>2;C=>3');
        System.assertEquals(3, result.size());
        System.assertEquals('1', result.get('A'));
        System.assertEquals('2', result.get('B'));
        System.assertEquals('3', result.get('C'));
    }

    @isTest
    static void testParseValueMap_TrimmedWhitespace() {
        Map<String, String> result = SIAE_UTIL_GenereLocaleConfig.parseValueMap(' FOO => BAR ');
        System.assertEquals(1, result.size());
        System.assertEquals('BAR', result.get('FOO'));
    }

    @isTest
    static void testParseValueMap_NoPairSeparator_Skipped() {
        Map<String, String> result = SIAE_UTIL_GenereLocaleConfig.parseValueMap('NOPAIR;A=>1');
        System.assertEquals(1, result.size());
        System.assertEquals('1', result.get('A'));
    }

    @isTest
    static void testParseValueMap_BlankKey_Skipped() {
        // '=>value' has blank sfValue → entry skipped
        Map<String, String> result = SIAE_UTIL_GenereLocaleConfig.parseValueMap('=>value;A=>1');
        System.assertEquals(1, result.size());
        System.assertEquals(false, result.containsKey(''), 'Blank key must be skipped');
    }

    // ────────────────────────────────────────────────────
    // mapPicklistValue()
    // ────────────────────────────────────────────────────

    @isTest
    static void testMapPicklistValue_Found() {
        String result = SIAE_UTIL_GenereLocaleConfig.mapPicklistValue('SI=>Y;NO=>N', 'SI', false);
        System.assertEquals('Y', result);
    }

    @isTest
    static void testMapPicklistValue_NotFound_Lenient() {
        String result = SIAE_UTIL_GenereLocaleConfig.mapPicklistValue('SI=>Y;NO=>N', 'MAYBE', false);
        System.assertEquals(null, result);
    }

    @isTest
    static void testMapPicklistValue_NotFound_Strict_ThrowsException() {
        try {
            SIAE_UTIL_GenereLocaleConfig.mapPicklistValue('SI=>Y;NO=>N', 'MAYBE', true);
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('MAYBE'), 'Error must mention the bad value');
        }
    }

    // ────────────────────────────────────────────────────
    // resolveOutboundValue()
    // ────────────────────────────────────────────────────

    @isTest
    static void testResolveOutbound_NullParam() {
        String result = SIAE_UTIL_GenereLocaleConfig.resolveOutboundValue(null, 'anyValue');
        System.assertEquals('anyValue', result);
    }

    @isTest
    static void testResolveOutbound_Integer_Valid() {
        SIAE_GenereLocaleParameter__mdt p = new SIAE_GenereLocaleParameter__mdt();
        p.SIAE_DataType__c = SIAE_UTIL_GenereLocaleConfig.DATA_TYPE_INTEGER;
        p.SIAE_ParameterName__c = 'testParam';

        String result = SIAE_UTIL_GenereLocaleConfig.resolveOutboundValue(p, '123');
        System.assertEquals('123', result);
    }

    @isTest
    static void testResolveOutbound_Integer_Decimal_Truncated() {
        SIAE_GenereLocaleParameter__mdt p = new SIAE_GenereLocaleParameter__mdt();
        p.SIAE_DataType__c = SIAE_UTIL_GenereLocaleConfig.DATA_TYPE_INTEGER;
        p.SIAE_ParameterName__c = 'testParam';

        String result = SIAE_UTIL_GenereLocaleConfig.resolveOutboundValue(p, '150.75');
        System.assertEquals('150', result);
    }

    @isTest
    static void testResolveOutbound_Integer_Invalid_ThrowsException() {
        SIAE_GenereLocaleParameter__mdt p = new SIAE_GenereLocaleParameter__mdt();
        p.SIAE_DataType__c = SIAE_UTIL_GenereLocaleConfig.DATA_TYPE_INTEGER;
        p.SIAE_ParameterName__c = 'testParam';

        try {
            SIAE_UTIL_GenereLocaleConfig.resolveOutboundValue(p, 'notAnInt');
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('notAnInt'));
        }
    }

    @isTest
    static void testResolveOutbound_Enumeration_WithValueMap() {
        SIAE_GenereLocaleParameter__mdt p = new SIAE_GenereLocaleParameter__mdt();
        p.SIAE_DataType__c    = SIAE_UTIL_GenereLocaleConfig.DATA_TYPE_ENUMERATION;
        p.SIAE_ParameterName__c = 'testEnum';
        p.SIAE_ValueMap__c    = 'SI=>Y;NO=>N';
        p.SIAE_EnumValues__c  = null;

        String result = SIAE_UTIL_GenereLocaleConfig.resolveOutboundValue(p, 'SI');
        System.assertEquals('Y', result);
    }

    @isTest
    static void testResolveOutbound_Enumeration_EnumValues_Valid() {
        SIAE_GenereLocaleParameter__mdt p = new SIAE_GenereLocaleParameter__mdt();
        p.SIAE_DataType__c    = SIAE_UTIL_GenereLocaleConfig.DATA_TYPE_ENUMERATION;
        p.SIAE_ParameterName__c = 'testEnum';
        p.SIAE_ValueMap__c    = null;
        p.SIAE_EnumValues__c  = 'SI;NO';

        String result = SIAE_UTIL_GenereLocaleConfig.resolveOutboundValue(p, 'SI');
        System.assertEquals('SI', result);
    }

    @isTest
    static void testResolveOutbound_Enumeration_EnumValues_Invalid_ThrowsException() {
        SIAE_GenereLocaleParameter__mdt p = new SIAE_GenereLocaleParameter__mdt();
        p.SIAE_DataType__c    = SIAE_UTIL_GenereLocaleConfig.DATA_TYPE_ENUMERATION;
        p.SIAE_ParameterName__c = 'testEnum';
        p.SIAE_ValueMap__c    = null;
        p.SIAE_EnumValues__c  = 'SI;NO';

        try {
            SIAE_UTIL_GenereLocaleConfig.resolveOutboundValue(p, 'FORSE');
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('FORSE'));
        }
    }

    @isTest
    static void testResolveOutbound_OtherDataType_PassThrough() {
        SIAE_GenereLocaleParameter__mdt p = new SIAE_GenereLocaleParameter__mdt();
        p.SIAE_DataType__c    = 'string';
        p.SIAE_ParameterName__c = 'testParam';

        String result = SIAE_UTIL_GenereLocaleConfig.resolveOutboundValue(p, 'freeText');
        System.assertEquals('freeText', result);
    }

    @isTest
    static void testResolveOutbound_NullDataType_PassThrough() {
        SIAE_GenereLocaleParameter__mdt p = new SIAE_GenereLocaleParameter__mdt();
        p.SIAE_DataType__c    = null;
        p.SIAE_ParameterName__c = 'testParam';

        String result = SIAE_UTIL_GenereLocaleConfig.resolveOutboundValue(p, 'rawValue');
        System.assertEquals('rawValue', result);
    }

    // ────────────────────────────────────────────────────
    // resolveTipoAutomezzo()
    // ────────────────────────────────────────────────────

    @isTest
    static void testResolveTipoAutomezzo_Trasporto() {
        String result = SIAE_UTIL_GenereLocaleConfig.resolveTipoAutomezzo(TIPO_TRASPORTO, null);
        System.assertEquals('C: autobus', result);
    }

    @isTest
    static void testResolveTipoAutomezzo_Ambulante_Fino() {
        String result = SIAE_UTIL_GenereLocaleConfig.resolveTipoAutomezzo(TIPO_AMBULANTE_SI, CIL_FINO);
        System.assertEquals('4: fino a 8mq e fino a 1500 cc', result);
    }

    @isTest
    static void testResolveTipoAutomezzo_Ambulante_Oltre() {
        String result = SIAE_UTIL_GenereLocaleConfig.resolveTipoAutomezzo(TIPO_AMBULANTE_SI, CIL_OLTRE);
        System.assertEquals('3: oltre 8mq o oltre 1500cc', result);
    }

    @isTest
    static void testResolveTipoAutomezzo_NonAmbulante_Fino() {
        String result = SIAE_UTIL_GenereLocaleConfig.resolveTipoAutomezzo(TIPO_AMBULANTE_NO, CIL_FINO);
        System.assertEquals('A: no ambulanti fino 1500cc', result);
    }

    @isTest
    static void testResolveTipoAutomezzo_NonAmbulante_Oltre() {
        String result = SIAE_UTIL_GenereLocaleConfig.resolveTipoAutomezzo(TIPO_AMBULANTE_NO, CIL_OLTRE);
        System.assertEquals('B: no ambulanti oltre 1500cc', result);
    }

    @isTest
    static void testResolveTipoAutomezzo_Unknown_ThrowsException() {
        try {
            SIAE_UTIL_GenereLocaleConfig.resolveTipoAutomezzo('TipoSconosciuto', CIL_FINO);
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('tipoAutomezzo non risolvibile'));
        }
    }

    @isTest
    static void testResolveTipoAutomezzo_Ambulante_UnknownCilindrata_ThrowsException() {
        // Ambulante SI but unknown cilindrata → no match → falls through to exception
        try {
            SIAE_UTIL_GenereLocaleConfig.resolveTipoAutomezzo(TIPO_AMBULANTE_SI, 'cilindrata sconosciuta');
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('tipoAutomezzo non risolvibile'));
        }
    }

    @isTest
    static void testResolveTipoAutomezzo_NonAmbulante_UnknownCilindrata_ThrowsException() {
        try {
            SIAE_UTIL_GenereLocaleConfig.resolveTipoAutomezzo(TIPO_AMBULANTE_NO, 'cilindrata sconosciuta');
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('tipoAutomezzo non risolvibile'));
        }
    }

    // ────────────────────────────────────────────────────
    // resolveUtilizzoNave()
    // ────────────────────────────────────────────────────

    @isTest
    static void testResolveUtilizzoNave_NonNumeric_ThrowsException() {
        try {
            SIAE_UTIL_GenereLocaleConfig.resolveUtilizzoNave(NAVE_COSTIERA, 'abc');
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('non numerico'));
        }
    }

    @isTest
    static void testResolveUtilizzoNave_Costiera_100() {
        System.assertEquals('4', SIAE_UTIL_GenereLocaleConfig.resolveUtilizzoNave(NAVE_COSTIERA, '100'));
    }

    @isTest
    static void testResolveUtilizzoNave_Costiera_200() {
        System.assertEquals('3', SIAE_UTIL_GenereLocaleConfig.resolveUtilizzoNave(NAVE_COSTIERA, '200'));
    }

    @isTest
    static void testResolveUtilizzoNave_Costiera_500() {
        System.assertEquals('2', SIAE_UTIL_GenereLocaleConfig.resolveUtilizzoNave(NAVE_COSTIERA, '500'));
    }

    @isTest
    static void testResolveUtilizzoNave_Costiera_800() {
        System.assertEquals('1', SIAE_UTIL_GenereLocaleConfig.resolveUtilizzoNave(NAVE_COSTIERA, '800'));
    }

    @isTest
    static void testResolveUtilizzoNave_Costiera_1000() {
        System.assertEquals('L', SIAE_UTIL_GenereLocaleConfig.resolveUtilizzoNave(NAVE_COSTIERA, '1000'));
    }

    @isTest
    static void testResolveUtilizzoNave_Costiera_Decimal() {
        // '100.0' → stripped to '100' → '4'
        System.assertEquals('4', SIAE_UTIL_GenereLocaleConfig.resolveUtilizzoNave(NAVE_COSTIERA, '100.0'));
    }

    @isTest
    static void testResolveUtilizzoNave_Traghetto_200() {
        System.assertEquals('4', SIAE_UTIL_GenereLocaleConfig.resolveUtilizzoNave(NAVE_TRAGHETTO, '200'));
    }

    @isTest
    static void testResolveUtilizzoNave_Traghetto_400() {
        System.assertEquals('3', SIAE_UTIL_GenereLocaleConfig.resolveUtilizzoNave(NAVE_TRAGHETTO, '400'));
    }

    @isTest
    static void testResolveUtilizzoNave_Traghetto_800() {
        System.assertEquals('2', SIAE_UTIL_GenereLocaleConfig.resolveUtilizzoNave(NAVE_TRAGHETTO, '800'));
    }

    @isTest
    static void testResolveUtilizzoNave_Traghetto_1200() {
        System.assertEquals('1', SIAE_UTIL_GenereLocaleConfig.resolveUtilizzoNave(NAVE_TRAGHETTO, '1200'));
    }

    @isTest
    static void testResolveUtilizzoNave_Traghetto_2000() {
        System.assertEquals('L', SIAE_UTIL_GenereLocaleConfig.resolveUtilizzoNave(NAVE_TRAGHETTO, '2000'));
    }

    @isTest
    static void testResolveUtilizzoNave_UnknownTipo_ThrowsException() {
        try {
            SIAE_UTIL_GenereLocaleConfig.resolveUtilizzoNave('Nave Sconosciuta', '100');
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('utilizzoNave non risolvibile'));
        }
    }
}