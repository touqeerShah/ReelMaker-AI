import { KokoroTTS } from "kokoro-js";
import fs from "node:fs";
import path from "node:path";

const model_id = "onnx-community/Kokoro-82M-v1.0-ONNX";
const outDir = "voices_out";
const text = "Hello, I am your AI voice for summarizing your story.";

fs.mkdirSync(outDir, { recursive: true });

const tts = await KokoroTTS.from_pretrained(model_id, { dtype: "q8" });

// Try to get voices from the library
let voices = [];
if (typeof tts.voices !== Object) {
    voices = Object.keys(tts.voices);
}
console.log("Voices:", (tts.voices));

// // Fallback list if list_voices() isn't available in your kokoro-js version
if (!Array.isArray(voices) || voices.length === 0) {
    voices = ["af_bella", "bf_emma", "am_adam", "bm_george"];
    console.warn(
        "tts.list_voices() not available or returned empty. Using fallback voices:",
        voices
    );
} else {
    console.log(`Found ${voices.length} voices:`, voices);
}

const safeName = (v) => v.replace(/[^a-zA-Z0-9_-]/g, "_");

for (const voice of voices) {
    try {
        console.log(`Generating voice: ${voice}`);
        const audio = await tts.generate(text, { voice });

        const filePath = path.join(outDir, `voice_${safeName(voice)}.wav`);
        audio.save(filePath);

        console.log(`Saved: ${filePath}`);
    } catch (err) {
        console.error(`Failed for voice "${voice}":`, err?.message ?? err);
    }
}

console.log("Done.");
