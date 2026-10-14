import express from 'express';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';

const app = express();
app.use(helmet());
app.use(express.json({ limit: '25kb' }));
app.use('/chat', rateLimit({ windowMs: 60_000, limit: 12, standardHeaders: 'draft-7', legacyHeaders: false }));

const instructions = `You are Hobu Baba, a Bangla-language family and parenting information assistant. Support expectant parents, mothers and fathers, and newborn care. Answer in the user's language. Give realistic evidence-aware, age-appropriate guidance; do not claim to have verified live clinical guidelines or facility services. Never diagnose, prescribe or adjust medication dosages. For emergencies (bleeding in pregnancy, seizures, severe headache, difficulty breathing, newborn fever under 3 months, lethargy, poor feeding, decreased fetal movements) lead with urgent in-person medical care. Avoid false reassurance and invite consultation with local clinicians. Never claim to replace a doctor. Keep answers concise, practical and compassionate.`;

app.post('/chat', async (req, res) => {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) return res.status(503).json({ error: 'Backend AI not configured' });
  const messages = req.body?.messages;
  if (!Array.isArray(messages) || messages.length === 0 || messages.length > 40) return res.status(400).json({ error: 'Invalid messages' });
  const cleaned = messages.slice(-20).map(x => ({ role: x?.role === 'assistant' ? 'assistant' : 'user', content: String(x?.content ?? '').slice(0, 2500) }));
  try {
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST', headers: { 'Authorization': `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ model: process.env.OPENAI_MODEL || 'gpt-4.1-mini', temperature: 0.3, messages: [{ role: 'system', content: instructions }, ...cleaned] }),
      signal: AbortSignal.timeout(30000),
    });
    if (!response.ok) return res.status(502).json({ error: 'AI provider unavailable' });
    const data = await response.json();
    return res.json({ reply: data.choices?.[0]?.message?.content || 'এখন উত্তর দেওয়া যাচ্ছে না।' });
  } catch (_) { return res.status(502).json({ error: 'AI backend connection failed' }); }
});
app.get('/health', (_req, res) => res.json({ ok: true }));
app.listen(Number(process.env.PORT || 3000));
