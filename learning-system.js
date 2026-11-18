(function () {
  "use strict";

  const SUPABASE_URL = "https://pjytoktykbaokkuhaera.supabase.co";
  const SUPABASE_KEY = "sb_publishable_jizTuUuoywy3im2S30OzXA_PfO4mWUY";
  const AUTH_STORAGE_KEY = "edusow-study-together-auth-v1";
  let clientPromise = null;

  function getClient() {
    if (!clientPromise) {
      clientPromise = (async function () {
        if (!window.supabase || typeof window.supabase.createClient !== "function") {
          throw new Error("EduSow's secure connection library could not load.");
        }
        const client = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY, {
          auth: {
            storageKey: AUTH_STORAGE_KEY,
            persistSession: true,
            autoRefreshToken: true,
            detectSessionInUrl: false
          }
        });
        const sessionResult = await client.auth.getSession();
        if (sessionResult.error) throw sessionResult.error;
        if (!sessionResult.data.session) {
          const signIn = await client.auth.signInAnonymously();
          if (signIn.error) throw signIn.error;
        }
        return client;
      })().catch(function (error) {
        clientPromise = null;
        throw error;
      });
    }
    return clientPromise;
  }

  function safeText(value, max, fallback) {
    const text = String(value == null ? "" : value).trim().slice(0, max);
    return text || fallback;
  }

  function hashQuestion(value) {
    const text = String(value || "").toLowerCase().replace(/\s+/g, " ").trim();
    let hash = 2166136261;
    for (let i = 0; i < text.length; i++) {
      hash ^= text.charCodeAt(i);
      hash = Math.imul(hash, 16777619);
    }
    return (hash >>> 0).toString(16).padStart(8, "0") + text.length.toString(16);
  }

  function getStudyContext() {
    let subject = "General";
    let topic = "Uncategorized";
    try {
      subject = safeText(localStorage.getItem("edusowLearningSubject"), 80, subject);
      topic = safeText(localStorage.getItem("edusowLearningTopic"), 160, topic);
    } catch (_) {}
    return { subject: subject, topic: topic };
  }

  async function recordQuizAttempt(payload) {
    const client = await getClient();
    const auth = await client.auth.getUser();
    if (auth.error || !auth.data.user) throw auth.error || new Error("Student session unavailable.");
    const userId = auth.data.user.id;
    const context = getStudyContext();
    const subject = safeText(payload.subject, 80, context.subject);
    const topic = safeText(payload.topic, 160, context.topic);
    const questions = Array.isArray(payload.questions) ? payload.questions.slice(0, 30) : [];
    const score = Math.max(0, Number(payload.score) || 0);
    const maxScore = Math.max(1, Number(payload.maxScore) || questions.length || 1);
    const title = safeText(payload.title, 200, "Practice quiz");

    const event = {
      user_id: userId,
      event_type: "quiz_attempt",
      subject: subject,
      topic: topic,
      title: title,
      score: score,
      max_score: maxScore,
      details: {
        percentage: Math.round((score / maxScore) * 100),
        question_count: questions.length,
        source: safeText(payload.source, 180, "EduSow Quiz Generator")
      }
    };

    const eventResult = await client.from("learning_events").insert(event).select("id").single();
    if (eventResult.error) throw eventResult.error;

    const mistakes = questions.filter(function (q) { return q && q.correct !== true; }).map(function (q) {
      const question = safeText(q.question, 1200, "Question");
      return {
        user_id: userId,
        question_hash: hashQuestion(question),
        subject: subject,
        topic: topic,
        question: question,
        selected_answer: safeText(q.selectedAnswer, 600, "Not answered"),
        correct_answer: safeText(q.correctAnswer, 600, "Answer unavailable"),
        explanation: safeText(q.explanation, 1600, ""),
        occurrences: 1,
        status: "needs_review",
        last_seen_at: new Date().toISOString(),
        updated_at: new Date().toISOString()
      };
    });

    if (mistakes.length) {
      const mistakeResult = await client.from("learning_mistakes").upsert(mistakes, {
        onConflict: "user_id,question_hash",
        ignoreDuplicates: false
      });
      if (mistakeResult.error) throw mistakeResult.error;
    }

    const key = subject.toLowerCase().trim() + "|" + topic.toLowerCase().trim();
    const prior = await client.from("learning_topic_progress")
      .select("attempts,correct_answers")
      .eq("user_id", userId)
      .eq("subject_key", subject.toLowerCase().trim())
      .eq("topic_key", topic.toLowerCase().trim())
      .maybeSingle();
    if (prior.error) throw prior.error;

    const attempts = (Number(prior.data && prior.data.attempts) || 0) + questions.length;
    const correctAnswers = (Number(prior.data && prior.data.correct_answers) || 0) + score;
    const mastery = attempts ? Math.round((correctAnswers / attempts) * 100) : 0;
    const reviewDays = mastery < 60 ? 1 : mastery < 80 ? 2 : 5;
    const nextReview = new Date(Date.now() + reviewDays * 86400000).toISOString();

    const progressResult = await client.from("learning_topic_progress").upsert({
      user_id: userId,
      subject: subject,
      topic: topic,
      subject_key: subject.toLowerCase().trim(),
      topic_key: topic.toLowerCase().trim(),
      attempts: attempts,
      correct_answers: correctAnswers,
      mastery_score: mastery,
      last_activity_at: new Date().toISOString(),
      next_review_at: nextReview,
      updated_at: new Date().toISOString()
    }, { onConflict: "user_id,subject_key,topic_key" });
    if (progressResult.error) throw progressResult.error;

    return { eventId: eventResult.data.id, mistakesRecorded: mistakes.length, mastery: mastery };
  }

  async function loadDashboard() {
    const client = await getClient();
    const auth = await client.auth.getUser();
    if (auth.error || !auth.data.user) throw auth.error || new Error("Student session unavailable.");
    const userId = auth.data.user.id;
    const results = await Promise.all([
      client.from("learning_events").select("*").eq("user_id", userId).order("occurred_at", { ascending: false }).limit(40),
      client.from("learning_mistakes").select("*").eq("user_id", userId).order("last_seen_at", { ascending: false }).limit(40),
      client.from("learning_topic_progress").select("*").eq("user_id", userId).order("mastery_score", { ascending: true }).limit(30)
    ]);
    for (const result of results) if (result.error) throw result.error;
    return {
      user: auth.data.user,
      events: results[0].data || [],
      mistakes: results[1].data || [],
      topics: results[2].data || []
    };
  }

  async function updateMistakeStatus(id, status) {
    if (!["needs_review", "practicing", "mastered"].includes(status)) throw new Error("Invalid mistake status.");
    const client = await getClient();
    const auth = await client.auth.getUser();
    if (auth.error || !auth.data.user) throw auth.error || new Error("Student session unavailable.");
    const result = await client.from("learning_mistakes")
      .update({ status: status, updated_at: new Date().toISOString() })
      .eq("id", id)
      .eq("user_id", auth.data.user.id);
    if (result.error) throw result.error;
  }

  async function askCoach(question, data, language) {
    const client = await getClient();
    const snapshot = data || await loadDashboard();
    const topics = snapshot.topics || [];
    const mistakes = snapshot.mistakes || [];
    const events = snapshot.events || [];
    const totalAttempts = topics.reduce((sum, item) => sum + (Number(item.attempts) || 0), 0);
    const totalCorrect = topics.reduce((sum, item) => sum + (Number(item.correct_answers) || 0), 0);
    const stats = {
      quizAttempts: events.filter(e => e.event_type === "quiz_attempt").length,
      questionsAttempted: totalAttempts,
      overallAccuracy: totalAttempts ? Math.round(totalCorrect / totalAttempts * 100) : null,
      openMistakes: mistakes.filter(m => m.status !== "mastered").length
    };
    const response = await client.functions.invoke("learning-coach", {
      body: {
        question: safeText(question, 1200, "Review my learning progress and recommend my next steps."),
        language: safeText(language, 40, "English"),
        stats: stats,
        weakTopics: topics.slice(0, 12),
        mistakes: mistakes.filter(m => m.status !== "mastered").slice(0, 10),
        recentActivity: events.slice(0, 10)
      }
    });
    if (response.error) {
      let message = response.error.message || "The learning coach could not respond.";
      try {
        const body = response.error.context && await response.error.context.json();
        if (body && body.error) message = body.error;
      } catch (_) {}
      throw new Error(message);
    }
    if (!response.data || !response.data.success || !response.data.answer) {
      throw new Error(response.data && response.data.error || "The learning coach returned an empty response.");
    }
    return response.data.answer;
  }

  window.EduSowLearning = {
    getClient: getClient,
    recordQuizAttempt: recordQuizAttempt,
    loadDashboard: loadDashboard,
    updateMistakeStatus: updateMistakeStatus,
    askCoach: askCoach,
    getStudyContext: getStudyContext
  };
})();