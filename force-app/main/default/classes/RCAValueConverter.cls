public class RCAValueConverter {
    public static Boolean asBoolean(Object value) {
        if (value == null) return false;
        if (value instanceof Boolean) return (Boolean) value;
        String normalized = String.valueOf(value).trim().toLowerCase();
        return normalized == 'true' || normalized == 'si' || normalized == 'sì' ||
               normalized == 'yes' || normalized == '1' || normalized == 'y';
    }

    public static String asString(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    public static Decimal asDecimal(Object value) {
        if (value == null) return null;
        if (value instanceof Decimal) return (Decimal) value;
        try {
            String normalized = String.valueOf(value).replace('%', '').trim().replace(',', '.');
            return Decimal.valueOf(normalized);
        } catch (Exception ignored) {
            return null;
        }
    }

    /**
     * Normalizza un valore a data funzionale senza applicare conversioni di timezone.
     * Per stringhe ISO mantiene il giorno espresso nel payload (YYYY-MM-DD).
     */
    public static Date asDate(Object value) {
        if (value == null) return null;
        if (value instanceof Date) return (Date) value;
        if (value instanceof Datetime) return ((Datetime) value).dateGMT();

        String rawValue = String.valueOf(value).trim();
        if (String.isBlank(rawValue) || rawValue.length() < 10) return null;

        try {
            return Date.valueOf(rawValue.substring(0, 10));
        } catch (Exception ignored) {
            return null;
        }
    }

    public static Datetime asDatetime(Object value) {
        if (value == null) return null;
        if (value instanceof Datetime) return (Datetime) value;

        String rawValue = String.valueOf(value).trim();
        if (String.isBlank(rawValue)) return null;

        try {
            return (Datetime) JSON.deserialize('"' + rawValue + '"', Datetime.class);
        } catch (Exception firstError) {
            try {
                return Datetime.valueOf(rawValue.replace('T', ' ').replace('Z', ''));
            } catch (Exception secondError) {
                return null;
            }
        }
    }

    public static Decimal roundMoney(Decimal value) {
        return value == null
            ? Decimal.valueOf(0)
            : value.setScale(2, RoundingMode.HALF_UP);
    }
}