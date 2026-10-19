/* EduSow Explain Materials: subject-aware interactive animation mode */
(function () {
  const originalRender = window.renderExplainLesson;
  const originalMove = window.moveExplainSlide;
  const originalGenerate = window.generateMaterialExplanation;
  let animationIndex = 0;
  let answers = {};

  function addText(parent, tag, value, className) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    node.textContent = String(value ?? "");
    parent.appendChild(node);
    return node;
  }

  function renderAnimation(content) {
    const demo = explainLesson && explainLesson.interactiveDemo;
    if (!demo || !Array.isArray(demo.stages) || !demo.stages.length) {
      addText(content, "p", "This lesson did not include an interactive demonstration. You can still use the slides and AI teacher modes.", "explain-animation-intro");
      return;
    }
    animationIndex = Math.max(0, Math.min(animationIndex, demo.stages.length - 1));
    const stage = demo.stages[animationIndex] || {};
    const path = document.createElement("div");
    path.className = "explain-animation-path";
    path.setAttribute("role", "group");
    path.setAttribute("aria-label", "Interactive lesson steps");
    demo.stages.forEach((item, index) => {
      const step = document.createElement("button");
      step.type = "button";
      step.className = "explain-animation-step" + (index === animationIndex ? " active" : "");
      step.setAttribute("aria-pressed", String(index === animationIndex));
      addText(step, "span", "Step " + (index + 1));
      addText(step, "strong", item.label || item.title || ("Explore " + (index + 1)));
      step.addEventListener("click", () => { animationIndex = index; renderExplainLesson(); });
      path.appendChild(step);
    });
    content.appendChild(path);

    const scene = document.createElement("section");
    scene.className = "explain-animation-stage";
    scene.setAttribute("aria-label", "Animated demonstration step " + (animationIndex + 1));
    const heading = document.createElement("div");
    heading.className = "explain-animation-stage-head";
    addText(heading, "span", (demo.kind || "interactive model").replace(/-/g, " ") + " · Step " + (animationIndex + 1) + " of " + demo.stages.length);
    addText(heading, "h4", stage.title || stage.label || "Explore this step");
    scene.appendChild(heading);

    const visual = document.createElement("div");
    visual.className = "explain-animation-visual";
    const objects = Array.isArray(stage.visuals) ? stage.visuals.slice(0, 3) : [];
    if (objects.length) {
      objects.forEach((object, index) => {
        if (index) addText(visual, "span", stage.connector || "→", "explain-animation-arrow");
        addText(visual, "div", object, "explain-animation-object");
      });
    } else {
      addText(visual, "div", stage.visual || stage.label || stage.title || "Observe this concept", "explain-animation-object");
    }
    scene.appendChild(visual);
    addText(scene, "div", stage.explanation || "", "explain-animation-description");
    content.appendChild(scene);

    if (stage.question && Array.isArray(stage.choices) && stage.choices.length >= 2) {
      const challenge = document.createElement("section");
      challenge.className = "explain-animation-challenge";
      addText(challenge, "h5", "🧩 Check your understanding");
      addText(challenge, "p", stage.question);
      const choiceList = document.createElement("div");
      choiceList.className = "explain-animation-choices";
      const selected = answers[animationIndex];
      stage.choices.slice(0, 4).forEach((choice, index) => {
        const option = document.createElement("button");
        option.type = "button";
        option.className = "explain-animation-choice";
        if (selected !== undefined && index === Number(stage.correctIndex)) option.classList.add("correct");
        else if (selected === index && selected !== Number(stage.correctIndex)) option.classList.add("incorrect");
        option.textContent = String(choice);
        option.setAttribute("aria-pressed", String(selected === index));
        option.addEventListener("click", () => { answers[animationIndex] = index; renderExplainLesson(); });
        choiceList.appendChild(option);
      });
      challenge.appendChild(choiceList);
      if (selected !== undefined) {
        const correct = selected === Number(stage.correctIndex);
        addText(challenge, "p", (correct ? "✓ " : "↻ ") + (stage.feedback || stage.explanation || "Review this step and try again."), "explain-animation-feedback");
      }
      content.appendChild(challenge);
    }
  }

  window.setExplainMode = function (mode) {
    explainMode = mode === "animation" ? "animation" : mode === "teacher" ? "teacher" : "slides";
    renderExplainLesson();
  };

  window.moveExplainSlide = function (direction) {
    if (explainMode !== "animation") {
      if (typeof originalMove === "function") return originalMove(direction);
      return;
    }
    const stages = explainLesson && explainLesson.interactiveDemo && explainLesson.interactiveDemo.stages || [];
    animationIndex = Math.max(0, Math.min(stages.length - 1, animationIndex + direction));
    renderExplainLesson();
  };

  window.renderExplainLesson = function () {
    if (explainMode !== "animation") {
      const hint = document.getElementById("explainAnimationHint");
      if (hint) hint.hidden = true;
      if (typeof originalRender === "function") return originalRender();
      return;
    }
    const content = document.getElementById("explainSlideContent");
    if (!content) return;
    content.replaceChildren();
    document.getElementById("explainSlidesMode")?.classList.remove("active");
    document.getElementById("explainTeacherMode")?.classList.remove("active");
    document.getElementById("explainAnimationMode")?.classList.add("active");
    const hint = document.getElementById("explainAnimationHint");
    if (hint) hint.hidden = false;
    document.getElementById("explainPresentationTitle").textContent = explainLesson?.title || "Your AI lesson";
    document.getElementById("explainPresentationSubtitle").textContent = "Explore a subject-specific demonstration and answer each checkpoint.";
    renderAnimation(content);
    const stages = explainLesson?.interactiveDemo?.stages || [];
    document.getElementById("explainSlideProgress").textContent = stages.length ? "Step " + (animationIndex + 1) + " of " + stages.length : "Interactive demonstration";
    document.getElementById("explainPrevious").disabled = animationIndex <= 0;
    document.getElementById("explainNext").disabled = !stages.length || animationIndex >= stages.length - 1;
    document.getElementById("explainPrevious").textContent = "← Previous step";
    document.getElementById("explainNext").textContent = stages.length && animationIndex >= stages.length - 1 ? "Demonstration complete ✓" : "Next step →";
  };

  if (typeof originalGenerate === "function") {
    window.generateMaterialExplanation = async function () {
      animationIndex = 0;
      answers = {};
      return originalGenerate.apply(this, arguments);
    };
  }
})();