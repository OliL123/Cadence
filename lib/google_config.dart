// Google OAuth 2.0 Web client ID for Cadence.
// This is a *public* client identifier (it ships in the web app and is safe to
// embed) — it is not a secret. Read-only Calendar access; the user still has to
// approve on Google's consent screen.
const googleClientId =
    '61656841317-scqpj3kd9empq6vio94degulpd40plvr.apps.googleusercontent.com';

// Read-only scope: lists the user's calendars and reads events. No write access.
const googleCalendarScope = 'https://www.googleapis.com/auth/calendar.readonly';
