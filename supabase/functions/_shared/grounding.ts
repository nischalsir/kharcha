// A check that what the AI wrote only quotes figures the user's own records
// actually contain.
//
// The model is told to use only numbers from the summary. This is what
// happens when it does not: every amount and percentage in its message is
// looked up in the summary, and a message with one that is not there is
// thrown away. The app then keeps the suggestion it wrote itself, from the
// same records, so the user never sees an invented figure.
//
// Pure, so it is unit tested without a model.

/** Counts and spans that mean nothing on their own: "7 days", "24 hours". */
const GENERIC = new Set([0, 1, 2, 3, 4, 5, 6, 7, 10, 12, 14, 24, 30, 100]);

function collect(value: unknown, numbers: number[], depth = 0): void {
  if (depth > 8 || value == null) return;
  if (typeof value === 'number') {
    if (Number.isFinite(value)) numbers.push(Math.abs(value));
    return;
  }
  if (typeof value === 'string') {
    // Numbers inside names and dates ("Shop 21", "2026-03-01") are the
    // user's own words too.
    for (const match of value.matchAll(/\d[\d,]*(?:\.\d+)?/g)) {
      const parsed = parseFloat(match[0].replace(/,/g, ''));
      if (Number.isFinite(parsed)) numbers.push(parsed);
    }
    return;
  }
  if (Array.isArray(value)) {
    for (const item of value) collect(item, numbers, depth + 1);
    return;
  }
  if (typeof value === 'object') {
    for (const item of Object.values(value as Record<string, unknown>)) {
      collect(item, numbers, depth + 1);
    }
  }
}

export interface QuotedNumber {
  text: string;
  value: number;
  /** An amount of money or a percentage: must be in the data exactly. */
  strict: boolean;
  /** Written with a `k`, e.g. `1.2k`: a rounded form. */
  abbreviated: boolean;
}

/** Every number written in [text], with how strictly it must be backed. */
export function quotedNumbers(text: string): QuotedNumber[] {
  const found: QuotedNumber[] = [];
  const re = /(npr|nrs|rs\.?|रु\.?)?\s*(\d[\d,]*(?:\.\d+)?)\s*(k\b|%)?/gi;
  for (const match of text.matchAll(re)) {
    const raw = match[2];
    let value = parseFloat(raw.replace(/,/g, ''));
    if (!Number.isFinite(value)) continue;
    const suffix = (match[3] ?? '').toLowerCase();
    const abbreviated = suffix === 'k';
    if (abbreviated) value *= 1000;
    const money = Boolean(match[1]) || raw.includes(',') || raw.includes('.');
    found.push({
      text: match[0].trim(),
      value,
      strict: money || suffix === '%' || abbreviated || value >= 100,
      abbreviated,
    });
  }
  return found;
}

/**
 * The numbers in [text] that the [data] does not back.
 *
 * A figure is backed when it rounds to a number found somewhere in the data
 * (the summary given to the model, and the context). Small bare counts such
 * as "7 days" are let through; amounts, percentages and anything of three
 * digits or more are not.
 */
export function ungroundedNumbers(text: string, ...data: unknown[]): string[] {
  const known: number[] = [];
  for (const item of data) collect(item, known);

  const backed = (quote: QuotedNumber) => {
    const tolerance = quote.abbreviated
      // "1.2k" for 1,234: within what the abbreviation can express.
      ? Math.max(50, quote.value * 0.05)
      : 0.5;
    return known.some((number) => Math.abs(number - quote.value) <= tolerance);
  };

  const missing: string[] = [];
  for (const quote of quotedNumbers(text)) {
    if (backed(quote)) continue;
    if (!quote.strict && GENERIC.has(quote.value)) continue;
    missing.push(quote.text);
  }
  return missing;
}
