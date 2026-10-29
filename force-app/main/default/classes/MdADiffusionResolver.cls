/**
 * @description : Risolve le tipologie di diffusione a partire dalla configurazione
 *                della Decision Table.
 *
 *                Chiave logica:
 *                  Catalogo
 *                + ProductCode
 *                + AttributeDefinitionCode
 *                + EffectiveFrom compreso nella validita'
 *
 *                Output:
 *                  AUDIO / VIDEO / RADIO
 *
 *                Il resolver non contiene mapping hardcoded prodotto/attributo -> tipologia.
 *                Gli attributi non configurati nella Decision Table vengono ignorati.
 *
 * @group       : NTT Data - SIAE
 * @last modified on : 10-29-2026
**/
public class MdADiffusionResolver {

    private static final String TYPE_AUDIO = 'AUDIO';
    private static final String TYPE_VIDEO = 'VIDEO';
    private static final String TYPE_RADIO = 'RADIO';

    public class Result {
        public Decimal hasAudio { get; private set; }
        public Decimal hasRadio { get; private set; }
        public Decimal hasVideo { get; private set; }

        private Result() {
            hasAudio = 0;
            hasRadio = 0;
            hasVideo = 0;
        }
    }

    public class ConfigurationIndex {
        private Map<String, List<SIAE_ODT_DiffusionTypeConfiguration__c>> configurationsByKey =
            new Map<String, List<SIAE_ODT_DiffusionTypeConfiguration__c>>();

        private ConfigurationIndex(List<SIAE_ODT_DiffusionTypeConfiguration__c> configurations) {
            if (configurations == null) {
                return;
            }

            for (SIAE_ODT_DiffusionTypeConfiguration__c configuration : configurations) {
                String key = buildKey(configuration.SIAE_Catalogo__c, configuration.SIAE_CodiceProdotto__c, configuration.SIAE_CodiceAttributo__c);

                if (String.isBlank(key)) {
                    continue;
                }

                if (!configurationsByKey.containsKey(key)) {
                    configurationsByKey.put(key, new List<SIAE_ODT_DiffusionTypeConfiguration__c>());
                }

                configurationsByKey.get(key).add(configuration);
            }
        }

        private String resolve(String catalogCode, String productCode, String attributeCode, Datetime effectiveFrom) {
            String key = buildKey(catalogCode, productCode, attributeCode);

            if (String.isBlank(key) || effectiveFrom == null || !configurationsByKey.containsKey(key)) {
                return null;
            }

            for (SIAE_ODT_DiffusionTypeConfiguration__c configuration : configurationsByKey.get(key)) {
                Boolean validFrom = configuration.SIAE_DataInizioValidita__c == null || configuration.SIAE_DataInizioValidita__c <= effectiveFrom;
                Boolean validTo = configuration.SIAE_DataFineValidita__c == null || configuration.SIAE_DataFineValidita__c >= effectiveFrom;

                if (validFrom && validTo) {
                    return configuration.SIAE_ClassificazioneDiffusione__c;
                }
            }

            return null;
        }
    }

    public static ConfigurationIndex load(String catalogCode, Set<String> productCodes) {
        if (String.isBlank(catalogCode) || productCodes == null || productCodes.isEmpty()) {
            return new ConfigurationIndex(new List<SIAE_ODT_DiffusionTypeConfiguration__c>());
        }

        List<SIAE_ODT_DiffusionTypeConfiguration__c> configurations = [
            SELECT SIAE_Catalogo__c, SIAE_CodiceProdotto__c, SIAE_CodiceAttributo__c,
                   SIAE_ClassificazioneDiffusione__c, SIAE_DataInizioValidita__c, SIAE_DataFineValidita__c
              FROM SIAE_ODT_DiffusionTypeConfiguration__c
              WHERE SIAE_Catalogo__c = :catalogCode
                AND SIAE_CodiceProdotto__c IN :productCodes
              ORDER BY SIAE_CodiceProdotto__c, SIAE_CodiceAttributo__c, SIAE_DataInizioValidita__c DESC
        ];

        return new ConfigurationIndex(configurations);
    }

    public static Result resolve(ConfigurationIndex configurationIndex, String catalogCode, String productCode, Datetime effectiveFrom, Map<String, String> attributeValuesByCode) {
        Result result = new Result();

        if (
            configurationIndex == null ||
            String.isBlank(catalogCode) ||
            String.isBlank(productCode) ||
            effectiveFrom == null ||
            attributeValuesByCode == null ||
            attributeValuesByCode.isEmpty()
        ) {
            return result;
        }

        for (String attributeCode : attributeValuesByCode.keySet()) {
            String attributeValue = attributeValuesByCode.get(attributeCode);

            if (!isActiveAttribute(attributeValue)) {
                continue;
            }

            String diffusionType = configurationIndex.resolve(catalogCode, productCode, attributeCode, effectiveFrom);
            applyDiffusionType(result, diffusionType);

            if (result.hasAudio == 1 && result.hasVideo == 1 && result.hasRadio == 1) {
                break;
            }
        }

        return result;
    }

    /* ========================= BUSINESS ========================= */

    /**
     * Per il mapping di diffusione consideriamo attivi solo attributi
     * numerici con valore > 0.
     *
     * Gli attributi tecnici/picklist presenti nel context vengono quindi
     * automaticamente esclusi dalle invocazioni.
     */
    @TestVisible
    private static Boolean isActiveAttribute(String attributeValue) {
        if (String.isBlank(attributeValue)) {
            return false;
        }

        Decimal numericValue = RCAValueConverter.asDecimal(attributeValue);

        return numericValue != null && numericValue > 0;
    }

    @TestVisible
    private static void applyDiffusionType(Result result, String diffusionType) {
        if (result == null || String.isBlank(diffusionType)) {
            return;
        }

        String normalized = diffusionType.trim().toUpperCase();

        if (TYPE_AUDIO == normalized) {
            result.hasAudio = 1;
        } else if (TYPE_VIDEO == normalized) {
            result.hasVideo = 1;
        } else if (TYPE_RADIO == normalized) {
            result.hasRadio = 1;
        }
    }

    @TestVisible
    private static String buildKey(String catalogCode, String productCode, String attributeCode) {
        if (String.isBlank(catalogCode) || String.isBlank(productCode) || String.isBlank(attributeCode)) {
            return null;
        }

        return catalogCode.trim().toUpperCase() + '|' + productCode.trim().toUpperCase() + '|' + attributeCode.trim().toUpperCase();
    }

}