import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import fetch from "node-fetch";
import * as dotenv from "dotenv";
import * as functionsV1 from "firebase-functions/v1";

dotenv.config();

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

// 🚨 IMPORTANT: The API Key is loaded via process.env for security in a real environment.
const GEMINI_API_KEY = process.env.GEMINI_API_KEY; 
console.log("🔑 GEMINI_API_KEY loaded:", !!GEMINI_API_KEY);
if (!GEMINI_API_KEY) {
  throw new Error("❌ Missing Gemini API key! Add GEMINI_API_KEY to .env file.");
}

interface GeminiResponse {
  candidates?: {
    content?: {
      parts?: { text?: string }[];
    };
  }[];
}

// 🌤 Detect current seasonal context (Updated for humor and absurdity)
function getSeasonalContext(): string {
  const month = new Date().getMonth();
  if ([11, 0, 1].includes(month))
    return "winter — the quiet sadness of a microwave meal";
  if ([2, 3, 4].includes(month))
    return "spring — confusing energy like a squirrel wearing glasses";
  if ([5, 6, 7].includes(month))
    return "summer — everything is slightly too sticky and loud";
  return "autumn — existential dread mixed with pumpkin spice";
}

// 🌍 Simple, humorous mood trends (Replacing 'calm' themes with absurd ones)
const moodTrends = [
    "a poorly hidden secret", 
    "the feeling of a broken keyboard",
    "waiting for an email that never arrives", 
    "the chaotic energy of a toddler's birthday party",
    "overthinking a very simple sandwich", 
    "a silent disco in a library", 
    "a robot trying to understand irony",
    "a forgotten password's gentle despair",
];

// 🌤 Generate absurd, funny, and simple prompts
async function generatePrompt(): Promise<string> {
  const seasonContext = getSeasonalContext();

  // Select a random, absurd mood
  const mood = moodTrends[Math.floor(Math.random() * moodTrends.length)];

  const systemPrompt = `You are an absurdist comedian and surrealist painter.
Generate ONE short drawing prompt (under 7 words) that is **funny, simple, and slightly absurd**.
It should blend the vibe of **${seasonContext}** with the funny tone of **${mood}**.
Rules:
- Keep it STRICTLY UNDER 7 words.
- Use simple, easy-to-read English words.
- Focus on concepts, feelings, or simple objects doing strange things.
- Avoid punctuation except commas or periods.
Examples of the new style:
  "A lonely banana considering math homework"
  "Invisible socks having a polite argument"
  "The internet sighing very quietly"
  "Confused toast floating near Mars"
  "A tiny ghost trying to use Wi-Fi"
  "Unopened letters discussing philosophy"
  "Pizza slices attending a meeting"
  "Slightly nervous clouds making soup"`;

  const userPrompt = `Generate one funny, absurd, and simple drawing prompt.
It should feel like ${seasonContext} and reflect the mood of ${mood}.
Use common English words only and keep it very short (under 7 words).`;

  const promptBody = {
    contents: [{ role: "user", parts: [{ text: userPrompt }] }],
    systemInstruction: { parts: [{ text: systemPrompt }] },
    generationConfig: {
      temperature: 0.9,
      topP: 0.9,
      topK: 40,
    },
  };

  try {
    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-09-2025:generateContent?key=${GEMINI_API_KEY}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(promptBody),
      }
    );

    const data = (await response.json()) as GeminiResponse;

    const text =
      data?.candidates?.[0]?.content?.parts?.[0]?.text?.trim() ||
      getFallbackPrompt();

    console.log("🌤 New Daily Prompt:", text);
    return text;
  } catch (error) {
    console.error("❌ Gemini API Error:", error);
    return getFallbackPrompt();
  }
}

// 🪴 Fallback prompt if Gemini fails (Updated for humor)
function getFallbackPrompt(): string {
  const fallbacks = [
    "A tired sock writing a novel",
    "Confused spaghetti studying history",
    "The wind trying on new shoes",
    "An umbrella arguing with rain",
    "A calculator feeling very judged",
  ];
  return fallbacks[Math.floor(Math.random() * fallbacks.length)];
}

// ✅ On-demand function — returns same prompt for 24 hrs, refreshes after midnight
export const generateDailyPrompt = functions.https.onRequest(
  async (req, res): Promise<void> => {
    try {
      const force = req.query.force === "true";
      const today = new Date().toLocaleDateString("en-US", {
        timeZone: "America/Chicago",
      });

      const ref = db.collection("prompts").doc("daily");
      const doc = await ref.get();

      if (!force && doc.exists && doc.data()?.date === today && doc.data()?.prompt) {
        res.status(200).json({
          success: true,
          prompt: doc.data()?.prompt,
          date: doc.data()?.date,
        });
        return;
      }

      const prompt = await generatePrompt();
      await ref.set({ prompt, date: today });

      res.status(200).json({
        success: true,
        prompt,
        date: today,
      });
    } catch (err) {
      console.error("❌ Error:", err);
      res.status(500).json({
        success: false,
        prompt: "Error generating prompt.",
      });
    }
  }
);

// 🔧 One-time backfill: populate `displayNameLower` for every existing user so
// case-insensitive friend search works for accounts created before the field existed.
// Call once after deploy:  GET https://<region>-<project>.cloudfunctions.net/backfillDisplayNameLower
export const backfillDisplayNameLower = functions.https.onRequest(
  async (_req, res): Promise<void> => {
    try {
      const snap = await db.collection("users").get();

      let updated = 0;
      let skipped = 0;
      let batch = db.batch();
      let pending = 0;

      for (const doc of snap.docs) {
        const data = doc.data();
        const displayName = (data.displayName as string) || "";
        if (!displayName) {
          skipped++;
          continue;
        }
        const expected = displayName.toLowerCase();
        if (data.displayNameLower === expected) {
          skipped++;
          continue;
        }

        batch.update(doc.ref, { displayNameLower: expected });
        updated++;
        pending++;

        // Firestore batches are capped at 500 writes.
        if (pending === 400) {
          await batch.commit();
          batch = db.batch();
          pending = 0;
        }
      }

      if (pending > 0) await batch.commit();

      console.log(`✅ Backfill complete. updated=${updated} skipped=${skipped}`);
      res.status(200).json({ success: true, updated, skipped });
    } catch (err) {
      console.error("❌ Backfill failed:", err);
      res.status(500).json({ success: false, error: String(err) });
    }
  }
);

export const scheduledDailyPrompt = functionsV1.pubsub
  .schedule("0 0 * * *") // every midnight UTC (6PM CST)
  .timeZone("America/Chicago")
  .onRun(async () => {
    try {
      console.log("🌙 Running scheduledDailyPrompt...");

      const chicagoNow = new Date().toLocaleDateString("en-US", {
        timeZone: "America/Chicago",
      });

      // 🔹 1. Delete Firestore drawings older than today
      const drawingsRef = db.collection("drawings");
      const drawingsSnap = await drawingsRef.get();

      let deletedDocs = 0;
      drawingsSnap.forEach(async (doc) => {
        const data = doc.data();
        const createdAt = data?.timestamp?.toDate?.();
        if (createdAt) {
          const docDate = createdAt.toLocaleDateString("en-US", {
            timeZone: "America/Chicago",
          });
          if (docDate !== chicagoNow) {
            await doc.ref.delete();
            deletedDocs++;
          }
        }
      });

      if (deletedDocs > 0) {
        console.log(`✅ Deleted ${deletedDocs} old Firestore drawings.`);
      } else {
        console.log("📭 No old Firestore drawings found to delete.");
      }

      // 🔹 2. Delete images from Firebase Storage older than today
      // NOTE: Ensure the bucket name is correct for your Firebase project
      const bucket = admin.storage().bucket("brush-ebc32.appspot.com"); 
      const [files] = await bucket.getFiles({ prefix: "drawings/" });

      let deletedFiles = 0;
      for (const file of files) {
        const [metadata] = await file.getMetadata();
        const updatedStr = metadata.updated;
        if (!updatedStr) continue; // skip if timestamp missing
        const updated = new Date(updatedStr);

        const fileDate = updated.toLocaleDateString("en-US", {
            timeZone: "America/Chicago",
        });

        if (fileDate !== chicagoNow) {
          await file.delete();
          console.log("🗑️ Deleted old drawing:", file.name);
          deletedFiles++;
        }
      }


      if (deletedFiles > 0) {
        console.log(`✅ Deleted ${deletedFiles} old files from Storage.`);
      } else {
        console.log("📁 No old drawings found in Storage to delete.");
      }

      // 🔹 3. Generate and save the new prompt
      const promptRef = db.collection("prompts").doc("daily");
      const doc = await promptRef.get();

      if (doc.exists && doc.data()?.date === chicagoNow) {
        console.log("🕒 Prompt already up to date for", chicagoNow);
        return null;
      }

      console.log("✨ Generating new prompt for", chicagoNow);
      const prompt = await generatePrompt();
      await promptRef.set({ prompt, date: chicagoNow });

      console.log("✅ New prompt saved:", prompt);
      return null;
    } catch (error) {
      console.error("❌ Scheduled prompt generation failed:", error);
      return null;
    }
  });