import { encodeBase64 } from 'https://deno.land/std@0.224.0/encoding/base64.ts';

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY')!;
const FROM_EMAIL = Deno.env.get('BACKSTORY_FROM_EMAIL') || 'onboarding@resend.dev';
const TO_EMAIL = 'backstories.fa@gmail.com';
const MAX_FILE_BYTES = 15 * 1024 * 1024;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const form = await req.formData();

    const playerFirstName = String(form.get('playerFirstName') || '').trim();
    const playerLastName = String(form.get('playerLastName') || '').trim();
    const email = String(form.get('email') || '').trim();
    const fullCharacterName = String(form.get('fullCharacterName') || '').trim();
    const commonName = String(form.get('commonName') || '').trim();
    const characterAge = String(form.get('characterAge') || '').trim();
    const characterRace = String(form.get('characterRace') || '').trim();
    const historyFile = form.get('historyFile');

    if (!email || !fullCharacterName || !commonName || !characterRace || !(historyFile instanceof File)) {
      return jsonResponse({ error: 'Missing a required field: email, full character name, common name, race, or history file.' }, 400);
    }
    if (historyFile.size === 0) {
      return jsonResponse({ error: 'The attached history file is empty.' }, 400);
    }
    if (historyFile.size > MAX_FILE_BYTES) {
      return jsonResponse({ error: 'The attached history file is too large (15MB max).' }, 400);
    }

    const fileBytes = new Uint8Array(await historyFile.arrayBuffer());
    const fileBase64 = encodeBase64(fileBytes);

    const bodyLines = [
      `Player: ${playerFirstName} ${playerLastName}`.trim(),
      `Email: ${email}`,
      `Full character name: ${fullCharacterName}`,
      `Goes by: ${commonName}`,
      `Character age: ${characterAge || 'not given'}`,
      `Character race: ${characterRace}`,
    ];

    const resendResp = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: FROM_EMAIL,
        to: [TO_EMAIL],
        reply_to: email,
        subject: `Backstory submission: ${fullCharacterName}`,
        text: bodyLines.join('\n'),
        attachments: [{ filename: historyFile.name, content: fileBase64 }],
      }),
    });

    if (!resendResp.ok) {
      const errText = await resendResp.text();
      return jsonResponse({ error: `Email service error: ${errText}` }, 502);
    }

    return jsonResponse({ ok: true });
  } catch (err) {
    return jsonResponse({ error: err instanceof Error ? err.message : 'Unknown error' }, 500);
  }
});
