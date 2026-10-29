/**
 * @description      Utility di accesso ai Custom Metadata Type di mapping del Genere Locale:
 *                   SIAE_GenereLocale__mdt (lookup Nome+Product → CodiceGenere) e
 *                   SIAE_GenereLocaleParameter__mdt (definizione parametri per Genere/Scope).
 *                   Espone load, getGenereCode, getParameters. Usa i metodi standard
 *                   getAll() di CMT (no SOQL, no limit consumption).
 * @author           Gaetano Iuliano - gaetano.iuliano@nttdata.com
 * @group            NTT Data — SIAE
 * @createdDate      2026-05-30
 * @lastModifiedDate 2026-06-11
 * @lastModifiedBy   Gaetano Iuliano
 */
public with sharing class SIAE_UTIL_GenereLocaleConfig {

    public static final String SCOPE_LOCALE = 'LOCALE';
    public static final String SCOPE_SPAZIO = 'SPAZIO';
    public static final String SCOPE_SCHEDA = 'SCHEDA';

    public static final String DATA_TYPE_INTEGER     = 'integer';
    public static final String DATA_TYPE_ENUMERATION = 'enumeration';

    private static final String VALUE_MAP_PAIR_SEPARATOR  = ';';
    private static final String VALUE_MAP_ENTRY_SEPARATOR = '=>';


    public static final String PARAM_TIPO_AUTOMEZZO = 'tipoAutomezzo';
    public static final String ATTR_TIPO_MEZZO      = 'SIAE-ATTR-CLASS';
    public static final String ATTR_CILINDRATA      = 'SIAE-ATTR-CILINDRATA';


    // v1.1: parametro rinominato 'utilizzoNave' -> 'utilizzo' (allineamento naming Mulesoft / parametri scheda)
    public static final String PARAM_UTILIZZO_NAVE = 'utilizzo';
    public static final String ATTR_TIPO_NAVE      = 'SIAE-ATTR-CLASS';
    public static final String ATTR_PASSEGGERI     = 'SIAE-ATTR-QTA';

    private static final Map<String, GenereConfig> cache = new Map<String, GenereConfig>();

    public class GenereConfig {
        public String codiceGenere;
        public List<SIAE_GenereLocaleParameter__mdt> localeParams =
            new List<SIAE_GenereLocaleParameter__mdt>();
        public List<SIAE_GenereLocaleParameter__mdt> spazioParams =
            new List<SIAE_GenereLocaleParameter__mdt>();
        public List<SIAE_GenereLocaleParameter__mdt> schedaParams =
            new List<SIAE_GenereLocaleParameter__mdt>();
    }


    public static GenereConfig load(String nomeGenere, String productCode) {
        String key = nomeGenere + '|' + productCode;
        if (cache.containsKey(key)) {
            return cache.get(key);
        }

        String codice = getGenereCode(nomeGenere, productCode);

        GenereConfig cfg = new GenereConfig();
        cfg.codiceGenere = codice;

        for (SIAE_GenereLocaleParameter__mdt p : SIAE_GenereLocaleParameter__mdt.getAll().values()) {
            if (codice.equals(p.SIAE_GenereCode__c)) {
                if (SCOPE_LOCALE.equals(p.SIAE_Scope__c)) {
                    cfg.localeParams.add(p);
                } else if (SCOPE_SPAZIO.equals(p.SIAE_Scope__c)) {
                    cfg.spazioParams.add(p);
                } else if (SCOPE_SCHEDA.equals(p.SIAE_Scope__c)) {
                    cfg.schedaParams.add(p);
                }
            }
        }

        cache.put(key, cfg);
        return cfg;
    }

  
    public static String getGenereCode(String nomeGenere, String productCode) {
        if (String.isBlank(nomeGenere) || String.isBlank(productCode)) {
            throw new IllegalArgumentException(
                'SIAE_UTIL_GenereLocaleConfig.getGenereCode: nomeGenere e productCode devono essere valorizzati sul Lineitem'
            );
        }

        for (SIAE_GenereLocale__mdt g : SIAE_GenereLocale__mdt.getAll().values()) {
            if (nomeGenere.equals(g.SIAE_GenereName__c)
                && productCode.equals(g.SIAE_ProductCode__c)) {
                return g.SIAE_GenereCode__c;
            }
        }
        throw new IllegalArgumentException(
            'Nessun mapping SIAE_GenereLocale__mdt per Genere=' + nomeGenere
            + ', Product=' + productCode
        );
    }

    public static List<SIAE_GenereLocaleParameter__mdt> getParameters(
        String genereCode,
        String scope
    ) {
        if (String.isBlank(genereCode) || String.isBlank(scope)) {
            throw new IllegalArgumentException(
                'SIAE_UTIL_GenereLocaleConfig.getParameters: genereCode e scope sono richiesti.'
            );
        }
        List<SIAE_GenereLocaleParameter__mdt> result = new List<SIAE_GenereLocaleParameter__mdt>();
        for (SIAE_GenereLocaleParameter__mdt p : SIAE_GenereLocaleParameter__mdt.getAll().values()) {
            if (genereCode.equals(p.SIAE_GenereCode__c) && scope.equals(p.SIAE_Scope__c)) {
                result.add(p);
            }
        }
        return result;
    }

    public static Map<String, String> parseValueMap(String raw) {
        Map<String, String> result = new Map<String, String>();
        if (String.isBlank(raw)) {
            return result;
        }
        for (String pair : raw.split(VALUE_MAP_PAIR_SEPARATOR)) {
            if (String.isBlank(pair) || !pair.contains(VALUE_MAP_ENTRY_SEPARATOR)) {
                continue;
            }
            String sfValue   = pair.substringBefore(VALUE_MAP_ENTRY_SEPARATOR).trim();
            String muleValue = pair.substringAfter(VALUE_MAP_ENTRY_SEPARATOR).trim();
            if (String.isNotBlank(sfValue)) {
                result.put(sfValue, muleValue);
            }
        }
        return result;
    }

    public static String mapPicklistValue(String valueMapConfig, String sfValue, Boolean strict) {
        Map<String, String> valueMap = parseValueMap(valueMapConfig);
        if (valueMap.containsKey(sfValue)) {
            return valueMap.get(sfValue);
        }
        if (strict == true) {
            throw new IllegalArgumentException(
                'Valore "' + sfValue + '" non presente nel mapping configurato: ' + valueMapConfig
            );
        }
        return null;
    }

    public static String resolveOutboundValue(SIAE_GenereLocaleParameter__mdt p, String sfRawValue) {
        if (p == null) {
            return sfRawValue;
        }
        String dataType = p.SIAE_DataType__c;

        if (DATA_TYPE_INTEGER.equals(dataType)) {
            try {
                String normalized = sfRawValue != null && sfRawValue.contains('.')
                    ? sfRawValue.substringBefore('.')
                    : sfRawValue;
                Integer.valueOf(normalized);
                return normalized;
            } catch (Exception e) {
                throw new IllegalArgumentException(
                    'Valore "' + sfRawValue + '" non castabile a integer per parametro '
                    + p.SIAE_ParameterName__c
                );
            }
        }

        if (DATA_TYPE_ENUMERATION.equals(dataType)) {
            if (String.isNotBlank(p.SIAE_ValueMap__c)) {
                return mapPicklistValue(p.SIAE_ValueMap__c, sfRawValue, true);
            }
            Set<String> allowed = new Set<String>(
                (p.SIAE_EnumValues__c != null ? p.SIAE_EnumValues__c : '').split(';')
            );
            if (!allowed.contains(sfRawValue)) {
                throw new IllegalArgumentException(
                    'Valore "' + sfRawValue + '" non in enum ' + p.SIAE_EnumValues__c
                    + ' per parametro ' + p.SIAE_ParameterName__c
                );
            }
            return sfRawValue;
        }

        return sfRawValue;
    }

    private static final String AUTOMEZZO_AMBULANTE_SI = 'Adibito al dettaglio ambulante';
    private static final String AUTOMEZZO_AMBULANTE_NO = 'Non adibito al dettaglio ambulante (fiere, propaganda)';
    private static final String AUTOMEZZO_TRASPORTO    = 'Trasporto passeggeri';
    private static final String CILINDRATA_FINO        = 'fino a 8 mq / fino a 1.500 cc';
    private static final String CILINDRATA_OLTRE       = 'oltre 8 mq / oltre 1.500 cc';

    public static String resolveTipoAutomezzo(String tipoMezzo, String cilindrata) {
        String tm  = tipoMezzo  == null ? '' : tipoMezzo.trim();
        String cil = cilindrata == null ? '' : cilindrata.trim();

        if (AUTOMEZZO_TRASPORTO.equalsIgnoreCase(tm)) {
            return 'C: autobus';
        }
        if (AUTOMEZZO_AMBULANTE_SI.equalsIgnoreCase(tm)) {
            if (CILINDRATA_FINO.equalsIgnoreCase(cil))  return '4: fino a 8mq e fino a 1500 cc';
            if (CILINDRATA_OLTRE.equalsIgnoreCase(cil)) return '3: oltre 8mq o oltre 1500cc';
        } else if (AUTOMEZZO_AMBULANTE_NO.equalsIgnoreCase(tm)) {
            if (CILINDRATA_FINO.equalsIgnoreCase(cil))  return 'A: no ambulanti fino 1500cc';
            if (CILINDRATA_OLTRE.equalsIgnoreCase(cil)) return 'B: no ambulanti oltre 1500cc';
        }
        throw new IllegalArgumentException(
            'tipoAutomezzo non risolvibile: tipoMezzo="' + tipoMezzo
            + '", cilindrata="' + cilindrata + '"'
        );
    }

    private static final String NAVE_COSTIERA  = 'Nave adibita a navigazione interna da costiera';
    private static final String NAVE_TRAGHETTO = 'Nave da crociera e da traghetto';

    public static String resolveUtilizzoNave(String tipoNave, String passeggeriRaw) {
        String tn = tipoNave == null ? '' : tipoNave.trim();

        Integer pax;
        try {
            String norm = (passeggeriRaw != null && passeggeriRaw.contains('.'))
                ? passeggeriRaw.substringBefore('.')
                : passeggeriRaw;
            pax = Integer.valueOf(norm == null ? null : norm.trim());
        } catch (Exception e) {
            throw new IllegalArgumentException(
                'utilizzoNave: numero passeggeri non numerico: "' + passeggeriRaw + '"'
            );
        }

        if (NAVE_COSTIERA.equalsIgnoreCase(tn)) {
            if (pax <= 100) return '4';
            if (pax <= 300) return '3';
            if (pax <= 600) return '2';
            if (pax <= 900) return '1';
            return 'L';
        }
        if (NAVE_TRAGHETTO.equalsIgnoreCase(tn)) {
            if (pax <= 300)  return '4';
            if (pax <= 500)  return '3';
            if (pax <= 1000) return '2';
            if (pax <= 1500) return '1';
            return 'L';
        }
        throw new IllegalArgumentException(
            'utilizzoNave non risolvibile: tipoNave="' + tipoNave
            + '", passeggeri="' + passeggeriRaw + '"'
        );
    }
}