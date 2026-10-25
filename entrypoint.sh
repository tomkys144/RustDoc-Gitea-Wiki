#!/bin/bash
set -e

# Get environment variables with sensible defaults
SOURCE_PATH="${SOURCE_PATH:-}"
WIKI_PATH="${WIKI_PATH:-wiki-content}"
COMMIT_MESSAGE="${COMMIT_MESSAGE:-Update documentation from Rust code}"
EXCLUDED_PATHS="${EXCLUDED_PATHS:-}"
EXTRACT_PRIVATE="${EXTRACT_PRIVATE:-false}"
MAX_DEFINITION_LINES="${MAX_DEFINITION_LINES:-50}"

# Convert excluded paths to array if provided
IFS=',' read -ra EXCLUDED_ARRAY <<< "$EXCLUDED_PATHS"

mkdir -p "${WIKI_PATH}"

# Create Home.md landing page
echo "# ${GITEA_REPOSITORY#*/} Documentation" > "${WIKI_PATH}/Home.md"
echo "" >> "${WIKI_PATH}/Home.md"
echo "This wiki contains automatically generated documentation from the Rust codebase." >> "${WIKI_PATH}/Home.md"
echo "" >> "${WIKI_PATH}/Home.md"
echo "## Documented Modules" >> "${WIKI_PATH}/Home.md"
echo "" >> "${WIKI_PATH}/Home.md"

# Function to check if a file path should be excluded
should_exclude() {
  local file="$1"
  for excluded in "${EXCLUDED_ARRAY[@]}"; do
    if [[ -n "$excluded" && "$file" == *"$excluded"* ]]; then
      return 0
    fi
  done
  return 1
}

# Universal source file discovery:
TARGET_DIRS=()
if [ -n "$SOURCE_PATH" ] && [ -d "$SOURCE_PATH" ]; then
  TARGET_DIRS=("$SOURCE_PATH")
elif [ -f "Cargo.toml" ]; then
  while IFS= read -r dir; do
    if [ -d "$dir/src" ]; then
      TARGET_DIRS+=("$dir/src")
    fi
  done < <(find . -name "Cargo.toml" -not -path "./Cargo.toml" -exec dirname {} \;)
  
  if [ -d "src" ]; then
    TARGET_DIRS+=("src")
  fi
else
  TARGET_DIRS=(".")
fi

# Process all discovered source directories
for search_dir in "${TARGET_DIRS[@]}"; do
  if [ ! -d "$search_dir" ]; then
    continue
  fi

  find "$search_dir" -name "*.rs" -type f | while read -r file; do
    if should_exclude "$file"; then
      echo "Skipping excluded file: $file"
      continue
    fi

    base_name=$(basename "$file" .rs)
    dir_path=$(dirname "$file")
    
    unique_name=$(echo "${dir_path//\//_}_${base_name}" | sed 's/^\.__//' | sed 's/^__//')
    output_file="${WIKI_PATH}/${unique_name}.md"
    
    echo "Processing $file into $output_file"
    
    echo "# $base_name ($dir_path)" > "$output_file"
    echo "" >> "$output_file"
    echo "Path: \`$file\`" >> "$output_file"
    echo "" >> "$output_file"
    
    # Extract module-level documentation (//! comments)
    grep -n "^[[:space:]]*//!" "$file" 2>/dev/null | sed 's/^[0-9]*://g' | sed 's/\/\/![[:space:]]*//' > "$output_file.module_docs" || true
    if [ -s "$output_file.module_docs" ]; then
      echo "## Module Documentation" >> "$output_file"
      echo "" >> "$output_file"
      cat "$output_file.module_docs" >> "$output_file"
      echo "" >> "$output_file"
    fi
    rm -f "$output_file.module_docs"
    
    echo "## Table of Contents" >> "$output_file"
    echo "" >> "$output_file"
    
    # Extract public items for the TOC and detailed generation
    {
      grep -n "^[[:space:]]*pub[[:space:]]\+mod" "$file" 2>/dev/null | sed -E 's/^([0-9]+):.*(pub[[:space:]]+mod[[:space:]]+[a-zA-Z0-9_]+).*/\1:\2/' || true
      grep -n "^[[:space:]]*pub[[:space:]]\+struct" "$file" 2>/dev/null | sed -E 's/^([0-9]+):.*(pub[[:space:]]+struct[[:space:]]+[a-zA-Z0-9_]+).*/\1:\2/' || true
      grep -n "^[[:space:]]*pub[[:space:]]\+enum" "$file" 2>/dev/null | sed -E 's/^([0-9]+):.*(pub[[:space:]]+enum[[:space:]]+[a-zA-Z0-9_]+).*/\1:\2/' || true
      grep -n "^[[:space:]]*pub[[:space:]]\+trait" "$file" 2>/dev/null | sed -E 's/^([0-9]+):.*(pub[[:space:]]+trait[[:space:]]+[a-zA-Z0-9_]+).*/\1:\2/' || true
      grep -n "^[[:space:]]*pub[[:space:]]\+fn" "$file" 2>/dev/null | sed -E 's/^([0-9]+):.*(pub[[:space:]]+fn[[:space:]]+[a-zA-Z0-9_]+).*/\1:\2/' || true
      grep -n "^[[:space:]]*pub[[:space:]]\+async[[:space:]]\+fn" "$file" 2>/dev/null | sed -E 's/^([0-9]+):.*(pub[[:space:]]+async[[:space:]]+fn[[:space:]]+[a-zA-Z0-9_]+).*/\1:\2/' || true
      grep -n "^[[:space:]]*pub[[:space:]]\+type" "$file" 2>/dev/null | sed -E 's/^([0-9]+):.*(pub[[:space:]]+type[[:space:]]+[a-zA-Z0-9_]+).*/\1:\2/' || true
      grep -n "^[[:space:]]*pub[[:space:]]\+const" "$file" 2>/dev/null | sed -E 's/^([0-9]+):.*(pub[[:space:]]+const[[:space:]]+[a-zA-Z0-9_]+).*/\1:\2/' || true

      if [ "$EXTRACT_PRIVATE" = "true" ]; then
        grep -n "^[[:space:]]*mod[[:space:]]" "$file" | grep -v "pub" 2>/dev/null | sed -E 's/^([0-9]+):.*(mod[[:space:]]+[a-zA-Z0-9_]+).*/\1:\2/' || true
        grep -n "^[[:space:]]*struct[[:space:]]" "$file" | grep -v "pub" 2>/dev/null | sed -E 's/^([0-9]+):.*(struct[[:space:]]+[a-zA-Z0-9_]+).*/\1:\2/' || true
      fi
    } | sort -n > "$output_file.items"
    
    while read -r line_info; do
      item_line=$(echo "$line_info" | cut -d: -f2-)
      if [[ "$item_line" =~ pub[[:space:]]+([a-zA-Z_]+)[[:space:]]+([a-zA-Z0-9_]+) ]]; then
        t_type="${BASH_REMATCH[1]}"
        t_name="${BASH_REMATCH[2]}"
        echo "* [$t_type $t_name](#${t_type}-${t_name})" >> "$output_file"
      fi
    done < "$output_file.items"
    
    echo "" >> "$output_file"
    echo "## Public Items" >> "$output_file"
    echo "" >> "$output_file"
    
    while read -r line_info; do
      line_num=$(echo "$line_info" | cut -d: -f1)
      item_line=$(echo "$line_info" | cut -d: -f2-)
      
      item_type=""
      item_name=""
      if [[ "$item_line" =~ pub[[:space:]]+([a-zA-Z_]+)[[:space:]]+([a-zA-Z0-9_]+) ]]; then
        item_type="${BASH_REMATCH[1]}"
        item_name="${BASH_REMATCH[2]}"
      fi
      
      if [ -n "$item_type" ] && [ -n "$item_name" ]; then
        echo "### $item_type $item_name" >> "$output_file"
        echo "" >> "$output_file"
        
        doc_start=$((line_num - 1))
        doc_lines=()
        while [ $doc_start -gt 0 ]; do
          doc_line=$(sed -n "${doc_start}p" "$file")
          if [[ "$doc_line" =~ ^[[:space:]]*\/\/\/ ]]; then
            comment=$(echo "$doc_line" | sed 's/^[[:space:]]*\/\/\/[[:space:]]*//')
            doc_lines=("$comment" "${doc_lines[@]}")
            doc_start=$((doc_start - 1))
          elif [[ "$doc_line" =~ ^[[:space:]]*$ ]] || [[ "$doc_line" =~ ^[[:space:]]*#\[ ]]; then
            doc_start=$((doc_start - 1))
          else
            break
          fi
        done
        
        echo "#### Definition" >> "$output_file"
        echo "" >> "$output_file"
        echo '```rust' >> "$output_file"
        def_line=$(sed -n "${line_num}p" "$file")
        echo "$def_line" >> "$output_file"
        echo '```' >> "$output_file"
        echo "" >> "$output_file"
        
        if [ ${#doc_lines[@]} -gt 0 ]; then
          echo "#### Documentation" >> "$output_file"
          echo "" >> "$output_file"
          for dl in "${doc_lines[@]}"; do
            echo "$dl" >> "$output_file"
          done
          echo "" >> "$output_file"
        fi
      fi
    done < "$output_file.items"
    
    rm -f "$output_file.items"
    
    echo "* [$unique_name](${unique_name})" >> "${WIKI_PATH}/Home.md"
  done
done

# Setup Git and push to Gitea Wiki repository if token is provided
if [ -n "$GITEA_TOKEN" ]; then
  git config --global user.email "actions@gitea.local"
  git config --global user.name "Gitea Actions Bot"

  echo "Cloning wiki repository..."
  PROTOCOL="$(echo $GITEA_SERVER_URL | grep :// | sed -e's,^\(.*://\).*,\1,g')"
  URL_WITHOUT_PROTOCOL="${GITEA_SERVER_URL/${PROTOCOL}/}"
  
  git clone "${PROTOCOL}oauth2:${GITEA_TOKEN}@${URL_WITHOUT_PROTOCOL}/${GITEA_REPOSITORY}.wiki.git" wiki-repo

  cp -r ${WIKI_PATH}/* wiki-repo/
  cd wiki-repo
  git add .

  if git diff --staged --quiet; then
    echo "No changes to commit"
  else
    git commit -m "${COMMIT_MESSAGE} (${GITEA_SHA:0:7})"
    git push origin master
    echo "Wiki successfully updated!"
  fi
else
  echo "GITEA_TOKEN not provided, skipping wiki push. Docs generated locally."
fi