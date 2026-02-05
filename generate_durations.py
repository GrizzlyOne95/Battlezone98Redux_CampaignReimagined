import os
import csv
import wave
import contextlib

def get_wav_duration(file_path):
    try:
        with contextlib.closing(wave.open(file_path, 'r')) as f:
            frames = f.getnframes()
            rate = f.getframerate()
            return frames / float(rate)
    except Exception as e:
        print(f"Error reading {file_path}: {e}")
        return None

def generate_csv(start_dir, output_file):
    with open(output_file, 'w', newline='') as csvfile:
        writer = csv.writer(csvfile)
        # No header needed, or strictly filename,duration
        # writer.writerow(['Filename', 'Duration'])
        
        for root, dirs, files in os.walk(start_dir):
            for file in files:
                if file.lower().endswith(".wav"):
                    full_path = os.path.join(root, file)
                    duration = get_wav_duration(full_path)
                    if duration is not None:
                        # Write just the filename (basename) and duration
                        # BZ2 assets are usually flattened or resolved by name
                        writer.writerow([file, f"{duration:.2f}"])
                        print(f"Processed: {file} -> {duration:.2f}s")

import sys

if __name__ == "__main__":
    start_dir = "."
    output_file = "durations.csv"
    
    if len(sys.argv) > 1:
        start_dir = sys.argv[1]
    if len(sys.argv) > 2:
        output_file = sys.argv[2]
        
    print(f"Scanning directory: {start_dir}")
    print(f"Outputting to: {output_file}")
    generate_csv(start_dir, output_file)
