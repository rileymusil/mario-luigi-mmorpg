// Basic bad-word filter for chat. It is deliberately simple: whole words
// (and common stretched spellings like "shiiit") are replaced with ****.
// Add words to the list as players find gaps.

const WORDS = [
  "fuck", "fucker", "fucking", "shit", "bitch", "bastard", "asshole", "dick",
  "cunt", "pussy", "cock", "whore", "slut", "fag", "faggot", "retard", "nigger",
  "nigga", "kys",
];

// "shit" also matches "shiiit"; letters may repeat.
const PATTERN = new RegExp(
  "\\b(" + WORDS.map((w) => [...w].map((c) => `${c}+`).join("")).join("|") + ")(s|es|ed|ing)?\\b",
  "gi",
);

export function cleanChat(text: string): string {
  return text.replace(PATTERN, (m) => "*".repeat(m.length));
}
