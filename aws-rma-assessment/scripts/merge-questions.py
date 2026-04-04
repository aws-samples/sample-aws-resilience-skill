#!/usr/bin/env python3
"""Merge all questions-group-{N}.json files into a single questions-data.json.

Usage: python3 scripts/merge-questions.py
Output: references/questions-data.json (for export/validation only, not used by LLM)
"""
import json, os

def main():
    ref_dir = os.path.join(os.path.dirname(__file__), '..', 'references')
    all_questions = []
    for i in range(1, 11):
        path = os.path.join(ref_dir, f'questions-group-{i}.json')
        with open(path) as f:
            group = json.load(f)
            all_questions.extend(group.get('questions', []))

    all_questions.sort(key=lambda q: q.get('id', 0))
    output = {"metadata": {"total_questions": len(all_questions), "generated": True}, "questions": all_questions}
    out_path = os.path.join(ref_dir, 'questions-data.json')
    with open(out_path, 'w', encoding='utf-8') as f:
        json.dump(output, f, indent=2, ensure_ascii=False)
        f.write('\n')
    print(f'Generated {out_path} with {len(all_questions)} questions')

if __name__ == '__main__':
    main()
