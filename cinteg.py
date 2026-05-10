import difflib
import sys
import os

def check_code_integrity(file1_path, file2_path):
    # Ensure both files exist before proceeding
    if not os.path.exists(file1_path) or not os.path.exists(file2_path):
        print(f"Error: One or both files could not be found.")
        return

    with open(file1_path, 'r', encoding='utf-8') as f1, \
         open(file2_path, 'r', encoding='utf-8') as f2:
        
        file1_lines = f1.readlines()
        file2_lines = f2.readlines()

    # Calculate the similarity ratio
    matcher = difflib.SequenceMatcher(None, file1_lines, file2_lines)
    similarity = matcher.ratio()
    change_percent = (1 - similarity) * 100

    # Generate the differences
    diff = list(difflib.ndiff(file1_lines, file2_lines))

    removed_parts = [line[2:].strip() for line in diff if line.startswith('- ')]
    added_parts = [line[2:].strip() for line in diff if line.startswith('+ ')]

    # Display Results
    print(f"Your code changed by {change_percent:.2f}%.")
    
    print(f"\nRemoved parts from {os.path.basename(file1_path)}:")
    if removed_parts:
        for line in removed_parts:
            print(f"- {line}")
    else:
        print("None")

    print(f"\nAdded parts detected in {os.path.basename(file2_path)}:")
    if added_parts:
        for line in added_parts:
            print(f"+ {line}")
    else:
        print("None")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python codeintegrity.py <original_file> <new_file>")
    else:
        check_code_integrity(sys.argv[1], sys.argv[2])