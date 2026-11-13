# Study Together release checklist

## Completed in the feature branch
- Standalone mobile-friendly Study Together page
- Anonymous Supabase identity flow with isolated browser storage key
- Private groups, owner/member roles, invitation-code creation and joining
- Lesson, quiz, flashcard and extracted study-text snapshots from the existing homepage
- Private PDF/JPG/PNG group uploads and signed downloads
- Group member list, activity feed, leave/remove/delete actions
- Additive database tables, RPC functions, RLS policies and private Storage bucket
- Homepage toolkit/navigation entry points and privacy disclosure

## Required before public release
1. In Supabase Dashboard > Authentication > Sign In / Providers, enable Anonymous Sign-ins.
2. Confirm the Data API exposes the public schema and that the authenticated role grants from the migration are active.
3. Test with two separate browsers: create a group in browser A, create an invite, join in browser B, and share/open each content type.
4. Verify a third non-member cannot read group rows, activity, shared items, or private files.
5. Test group deletion removes files before deleting the database group.
6. Review Supabase security advisor notices. The three public SECURITY DEFINER RPCs are intentional and validate the current anonymous identity, owner rights, invitation hashes and limits.
7. Run regression checks on the existing quiz, flashcards, Explain Materials, study materials and timetable tools.
