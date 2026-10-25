"""
Scoring for the four FYP 2 evaluation metrics. These functions only compute from REAL responses
that participants submit; the project contains no sample or invented results.

  * System Usability Scale (SUS): 10 items, 1-5. Odd items score (r - 1), even items (5 - r);
    the sum is multiplied by 2.5, giving 0-100.
  * User satisfaction: 5-point Likert items, reported as mean and percentage of 4-5 ("agree").
  * Task completion rate: successes / attempts x 100.
  * Calculation accuracy: automated tests (see tests/ and docs/evaluation/TEST_REPORT.md).
"""
from statistics import mean, pstdev
from typing import List

SUS_ITEMS = [
    "I think that I would like to use NutriFit frequently.",
    "I found NutriFit unnecessarily complex.",
    "I thought NutriFit was easy to use.",
    "I think that I would need the support of a technical person to be able to use NutriFit.",
    "I found the various functions in NutriFit were well integrated.",
    "I thought there was too much inconsistency in NutriFit.",
    "I would imagine that most people would learn to use NutriFit very quickly.",
    "I found NutriFit very cumbersome to use.",
    "I felt very confident using NutriFit.",
    "I needed to learn a lot of things before I could get going with NutriFit.",
]

SATISFACTION_ITEMS = [
    "The recipe quantities recommended for me matched my nutrition targets.",
    "The remaining daily nutrition information was clear and useful.",
    "Choosing a meal type and answering the next-meal question was easy.",
    "I trust the nutrition values shown by NutriFit.",
    "NutriFit helped me follow my coach's nutrition plan.",
    "I am satisfied with NutriFit overall.",
]

TASKS = [
    ("T1", "Log in and find today's remaining Calories, Protein, Carbs and Fat."),
    ("T2", "Select a meal type and answer the 'another meal today?' question."),
    ("T3", "Choose a recipe and run the ingredient optimization."),
    ("T4", "Read the optimized ingredient weights and the target-vs-recipe comparison."),
    ("T5", "Confirm that you ate the meal and check that the remaining nutrition updated."),
    ("T6", "Open the daily adherence summary and say whether today is on target."),
    ("T7", "(Coach) Open a client, read the adherence rate and change the client's targets."),
]


class EvaluationError(ValueError):
    pass


def _check(responses: List[int], n: int):
    if not isinstance(responses, list) or len(responses) != n:
        raise EvaluationError(f"Exactly {n} answers are required")
    if any((not isinstance(r, int)) or isinstance(r, bool) or not 1 <= r <= 5 for r in responses):
        raise EvaluationError("Every answer must be a whole number from 1 to 5")


def sus_score(responses: List[int]) -> float:
    _check(responses, 10)
    total = sum((r - 1) if i % 2 == 0 else (5 - r) for i, r in enumerate(responses))
    return total * 2.5


def sus_grade(score: float) -> str:
    """Common interpretation bands (Bangor et al.); 68 is the usual benchmark average."""
    if score >= 80.3: return "Excellent (A)"
    if score >= 68: return "Good / above average"
    if score >= 51: return "Marginal / below average"
    return "Poor"


def satisfaction_score(responses: List[int]) -> dict:
    _check(responses, len(SATISFACTION_ITEMS))
    return {"mean": round(mean(responses), 2), "agreePct": round(sum(1 for r in responses if r >= 4) / len(responses) * 100, 1)}


def task_completion(results: List[dict]) -> dict:
    """results: [{taskId, success(bool)}...] -> overall and per-task completion rate."""
    if not results:
        return {"attempts": 0, "successes": 0, "rate": None, "perTask": {}}
    per = {}
    for r in results:
        t = per.setdefault(r["taskId"], [0, 0])
        t[0] += 1
        t[1] += 1 if r["success"] else 0
    ok = sum(1 for r in results if r["success"])
    return {"attempts": len(results), "successes": ok, "rate": round(ok / len(results) * 100, 1),
            "perTask": {k: {"attempts": a, "successes": s, "rate": round(s / a * 100, 1)} for k, (a, s) in sorted(per.items())}}


def summarize(sus_list: List[List[int]], sat_list: List[List[int]], tasks: List[dict]) -> dict:
    scores = [sus_score(r) for r in sus_list]
    sat = [satisfaction_score(r) for r in sat_list]
    return {
        "participantsSUS": len(scores),
        "susMean": round(mean(scores), 1) if scores else None,
        "susSD": round(pstdev(scores), 1) if len(scores) > 1 else None,
        "susGrade": sus_grade(mean(scores)) if scores else None,
        "participantsSatisfaction": len(sat),
        "satisfactionMean": round(mean(s["mean"] for s in sat), 2) if sat else None,
        "satisfactionAgreePct": round(mean(s["agreePct"] for s in sat), 1) if sat else None,
        "tasks": task_completion(tasks),
    }
