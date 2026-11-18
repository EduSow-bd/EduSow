# EduSow Supabase Edge Functions

## Explain Materials

The frontend in index.html calls the explain-materials Edge Function. Its source is in supabase/functions/explain-materials/index.ts.

### Deploy it to the existing Supabase project

GitHub Pages only deploys website files; it does not deploy Supabase Edge Functions automatically.

1. Open the Supabase project used by EduSow.
2. Open Edge Functions and create a function named explain-materials.
3. Copy the source from supabase/functions/explain-materials/index.ts in this repository into the function editor and deploy it.
4. In the function's secrets/settings, confirm GEMINI_API_KEY is set. Reuse the project's existing Gemini secret; never place this secret in website JavaScript or GitHub.
5. Set gateway JWT verification to match the existing public AI generation functions. The current frontend invokes it without a signed-in user, so mandatory user-JWT verification will cause requests to fail.
6. Test with a short, non-sensitive PDF or JPG, extract its text, and click Explain Materials in both English and Bangla.

### Request/response

The frontend sends { text, language, detail, images }, where language is english or bangla, detail is simple, balanced, or detailed, and images is an optional list of up to five resized original PDF/image pages. The function sends both extracted text and image parts to Gemini Vision so it can explain diagrams, charts, maps, tables, labels, arrows, and other visual relationships. If visual input is rejected by the provider, the function retries using the original text-only request. The function returns the existing schema { success, title, teacherLabel, exampleLabel, slides, language }; interactive slides and follow-up chat remain unchanged.

### Important operational note

This function processes text through the configured Gemini API and is called from a public website. Before promoting it widely, add server-side abuse protection/rate limits and review AI provider usage and billing. Do not upload confidential or sensitive documents.

## Intelligent Learning Coach

The `learning-dashboard.html` page uses `learning-system.js` to record completed quizzes, study sessions, topic progress and mistakes in the Supabase tables created by `supabase/migrations/20261118135237_intelligent_learning_core.sql`.

The frontend and Study Together share the same Supabase anonymous-session storage key so the student's pseudonymous identity is consistent across both experiences. Learning records are protected by owner-scoped RLS policies. The dashboard includes a control to delete the current session's learning records.

The Personal AI Learning Coach is deployed as the `learning-coach` Edge Function. Its source is in `supabase/functions/learning-coach/index.ts`. It requires the existing `GEMINI_API_KEY` Supabase secret and gateway JWT verification is enabled. The function receives a compact learning summary, recent mistakes, topic progress and the student's question; it does not query the database directly.
