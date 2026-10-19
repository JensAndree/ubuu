#!/usr/bin/env bash
# ubuu.sh - create a single compressed backup archive (tgz, zip, bzip, rar),
#           optionally encrypted with openssl
set -euo pipefail

PROG_SOURCE='https://github.com/JensAndree/ubuu/'
PROG_VERSION='0.1.0'
PROG=${0##*/}
INPUT="" COMP="" OUT=""
DATETIME=0 SYMCOPY=0 VERBOSE=0 FORCE=0 PREVIEW=0 ENCRYPT=0
ENC_ALGO="aes-256-cbc"      # only algorithm for now; see encrypt_file()
PASSWORD=""
LIST="" FINAL="" TXT="" PARTIAL="" ENCPART=""

cleanup() { rm -f -- "$LIST" "$FINAL" "$TXT" "$PARTIAL" "$ENCPART"; }
trap cleanup EXIT

die()  { printf '%s: error: %s\n' "$PROG" "$*" >&2; exit 1; }
warn() { printf '%s: warning: %s\n' "$PROG" "$*" >&2; }
log()  { if (( VERBOSE )); then printf '[ubuu] %s\n' "$*" >&2; fi; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }

usage() {
  cat <<EOF
Usage: $PROG -I "PATH[;PATH...]" -c FORMAT -o NAME [options]

Ultimate BackUp Utility in bash. Very simple but fast and reliable. And of course Open Source. 
Creates a single compressed archive of the given paths, optionally encrypted if your openssl supports it. 
The archive can be unpacked on any system with the same compression format. 
The password is not stored anywhere, so make sure to remember it!



Mandatory:
  -I, --input PATHS        Paths to back up, separated by ';' (quote the whole value).
                           A trailing /* includes everything below (recursively).
                           Other wildcards (*, ?, [..]) are resolved too.
  -c, --compression FMT    tgz | zip | bzip | rar
  -o, --output NAME        Output file name (extension is added if missing)

Options:
  -C, --encrypt            Encrypt the backup (openssl enc -aes-256-cbc -salt).
                           You are asked for a password; ".enc" is appended to the file name.
  -d, --datetime           Append _YYYYmmdd_HHMMSS to the file name
  -s, --symlink-copy       Store symlinks as copies of what they point to
                           (default: store the symlinks themselves)
  -v, --verbose            Print progress while running
  -f, --force              Overwrite the output file if it already exists
  -p, --preview            List everything that would be archived, then exit
  -h, --help               Show this help

Source code: $PROG_SOURCE
Version: $PROG_VERSION

Examples:
  $PROG -I "/etc/nginx;\$HOME/My Documents/*" -c tgz -o /tmp/bk -d -v
  $PROG -I "./src;./docs" -c zip -o backup -p
  $PROG -I "./secrets" -c tgz -o vault -C
EOF
}

need_arg() { (( $# >= 2 )) || die "option $1 requires a value"; }

# ---------- argument parsing ----------
if (( $# == 0 )); then usage; exit 1; fi

# expand clustered short flags such as -dv into -d -v
args=()
for a in "$@"; do
  if [[ $a =~ ^-[dsvfpC]{2,}$ ]]; then
    for (( i = 1; i < ${#a}; i++ )); do args+=("-${a:i:1}"); done
  else
    args+=("$a")
  fi
done
set -- "${args[@]}"

while (( $# )); do
  case "$1" in
    -I|--input)         need_arg "$@"; INPUT+="${INPUT:+;}$2"; shift 2 ;;
    --input=*)          INPUT+="${INPUT:+;}${1#*=}"; shift ;;
    -c|--compression)   need_arg "$@"; COMP="$2"; shift 2 ;;
    --compression=*)    COMP="${1#*=}"; shift ;;
    -o|--output)        need_arg "$@"; OUT="$2"; shift 2 ;;
    --output=*)         OUT="${1#*=}"; shift ;;
    -C|--encrypt)       ENCRYPT=1; shift ;;
    -d|--datetime)      DATETIME=1; shift ;;
    -s|--symlink-copy)  SYMCOPY=1; shift ;;
    -v|--verbose)       VERBOSE=1; shift ;;
    -f|--force)         FORCE=1; shift ;;
    -p|--preview)       PREVIEW=1; shift ;;
    -h|--help)          usage; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

[[ -n $INPUT ]] || die "-I (input paths) is mandatory"
[[ -n $COMP  ]] || die "-c (compression format) is mandatory"
[[ -n $OUT   ]] || die "-o (output file name) is mandatory"

# ---------- compression format ----------
COMP_L=$(printf '%s' "$COMP" | tr '[:upper:]' '[:lower:]')
case "$COMP_L" in
  tgz|tar.gz|targz|gz)                  FMT=tgz;  EXT=".tgz" ;;
  bzip|bzip2|bz2|tbz|tbz2|tar.bz2)      FMT=bzip; EXT=".tar.bz2" ;;
  zip)                                  FMT=zip;  EXT=".zip" ;;
  rar)                                  FMT=rar;  EXT=".rar" ;;
  *) die "unsupported compression format '$COMP' (use tgz, zip, bzip or rar)" ;;
esac

# ---------- encryption ----------
# To add another algorithm later: add a case here (support check) and one in encrypt_file().
if (( ENCRYPT )); then
  need_cmd openssl
  case "$ENC_ALGO" in
    aes-256-cbc)
      # fail now rather than after a long archiving run if this openssl lacks -pbkdf2
      openssl enc -aes-256-cbc -salt -pbkdf2 -iter 1 -pass pass:x \
        -in /dev/null -out /dev/null 2>/dev/null \
        || die "this openssl does not support -pbkdf2 (OpenSSL 1.1.1+ or LibreSSL 3.1+ needed)" ;;
    *) die "unsupported encryption algorithm: $ENC_ALGO" ;;
  esac
  umask 077     # keep the temporary plaintext archive private
fi

encrypt_file() {   # usage: encrypt_file INFILE OUTFILE  (password taken from $PASSWORD)
  case "$ENC_ALGO" in
    aes-256-cbc)
      printf '%s\n' "$PASSWORD" \
        | openssl enc -aes-256-cbc -salt -pbkdf2 -iter 600000 -pass stdin -in "$1" -out "$2" ;;
    *) die "unsupported encryption algorithm: $ENC_ALGO" ;;
  esac
}

read_password() {
  # read from the terminal so the password never appears in argv, history or the environment
  { : < /dev/tty; } 2>/dev/null || die "-C needs a terminal to ask for the password"
  local p1 p2
  read -r -s -p "Encryption password: " p1 < /dev/tty; printf '\n' >&2
  [[ -n $p1 ]] || die "password must not be empty"
  read -r -s -p "Repeat password: " p2 < /dev/tty; printf '\n' >&2
  [[ $p1 == "$p2" ]] || die "passwords do not match"
  PASSWORD=$p1
}

# ---------- output file name ----------
[[ $OUT != */ ]] || die "output name must be a file name, not a directory"
if (( ENCRYPT )); then OUT=${OUT%.enc}; fi
BASE=${OUT%"$EXT"}
if (( DATETIME )); then BASE+="_$(date +%Y%m%d_%H%M%S)"; fi
OUT_FINAL="$BASE$EXT"
if (( ENCRYPT )); then OUT_FINAL+=".enc"; fi

OUT_DIR=$(dirname -- "$OUT_FINAL")
[[ -d $OUT_DIR ]] || die "output directory does not exist: $OUT_DIR"
[[ ! -d $OUT_FINAL ]] || die "output path is a directory: $OUT_FINAL"

OUT_EXISTS=0
if [[ -e $OUT_FINAL || -L $OUT_FINAL ]]; then
  OUT_EXISTS=1
  if (( ! FORCE && ! PREVIEW )); then
    die "output file exists: $OUT_FINAL (use -f to overwrite)"
  fi
fi

# ---------- resolve input paths ----------
expand_glob() {
  local IFS=''
  shopt -s nullglob dotglob
  GLOB_MATCHES=( $1 )
  shopt -u nullglob dotglob
}

ITEMS=()
RAW=()
IFS=';' read -r -a RAW <<< "$INPUT" || true

for p in ${RAW[@]+"${RAW[@]}"}; do
  # trim surrounding whitespace
  p="${p#"${p%%[![:space:]]*}"}"
  p="${p%"${p##*[![:space:]]}"}"
  [[ -n $p ]] || continue
  if [[ $p == "~" || $p == "~/"* ]]; then p="$HOME${p:1}"; fi

  case $p in
    *[\*\?\[]*)
      GLOB_MATCHES=()
      expand_glob "$p"
      if (( ${#GLOB_MATCHES[@]} == 0 )); then
        if [[ -e $p || -L $p ]]; then
          ITEMS+=("$p")                      # literal name that looks like a glob
        else
          die "no match for: $p"
        fi
      else
        log "pattern '$p' matched ${#GLOB_MATCHES[@]} item(s)"
        for m in "${GLOB_MATCHES[@]}"; do
          if [[ $m == -* ]]; then m="./$m"; fi
          ITEMS+=("$m")
        done
      fi
      ;;
    *)
      while [[ ${#p} -gt 1 && $p == */ ]]; do p=${p%/}; done
      [[ -e $p || -L $p ]] || die "path does not exist: $p"
      if [[ $p == -* ]]; then p="./$p"; fi
      ITEMS+=("$p")
      ;;
  esac
done

(( ${#ITEMS[@]} > 0 )) || die "no input paths given"

# ---------- build the file list (NUL-delimited) ----------
LIST=$(mktemp "${TMPDIR:-/tmp}/ubuu.list.XXXXXX")
FINAL=$(mktemp "${TMPDIR:-/tmp}/ubuu.final.XXXXXX")

for item in "${ITEMS[@]}"; do
  log "scanning: $item"
  if (( SYMCOPY )); then
    # follow symlinks; broken links cannot be copied, so skip them
    find -L "$item" -type l -print0 2>/dev/null \
      | while IFS= read -r -d '' b; do warn "skipping broken symlink: $b"; done || true
    find -L "$item" ! -type l -print0 >> "$LIST" \
      || warn "some entries under '$item' could not be read"
  else
    find "$item" -print0 >> "$LIST" \
      || warn "some entries under '$item' could not be read"
  fi
done

# de-duplicate, sort (parents sort before children) and never include the output file itself
LC_ALL=C sort -zu "$LIST" | while IFS= read -r -d '' f; do
  if (( OUT_EXISTS )) && [[ $f -ef $OUT_FINAL ]]; then continue; fi
  printf '%s\0' "$f"
done > "$FINAL"

COUNT=$(( $(tr -cd '\0' < "$FINAL" | wc -c) ))
(( COUNT > 0 )) || die "nothing to back up"

# ---------- preview ----------
if (( PREVIEW )); then
  printf 'Backup preview\n'
  printf '  Format      : %s\n' "$FMT"
  printf '  Output      : %s%s\n' "$OUT_FINAL" "$( (( OUT_EXISTS )) && echo ' (exists)' || true )"
  if (( ENCRYPT )); then
    printf '  Encryption  : %s (password asked at run time)\n' "$ENC_ALGO"
  else
    printf '  Encryption  : none\n'
  fi
  if (( SYMCOPY )); then
    printf '  Symlinks    : copied as files/directories\n'
  else
    printf '  Symlinks    : stored as links\n'
  fi
  printf '  Entries     : %d\n' "$COUNT"
  printf '  Legend      : d=directory  l=symlink  f=file\n\n'
  while IFS= read -r -d '' f; do
    if [[ -L $f && $SYMCOPY -eq 0 ]]; then t=l
    elif [[ -d $f ]]; then t=d
    else t=f
    fi
    printf '%s  %s\n' "$t" "$f"
  done < "$FINAL"
  exit 0
fi

# ---------- ask for the password up front (before the long archiving step) ----------
if (( ENCRYPT )); then read_password; fi

# ---------- create the archive ----------
PARTIAL="${BASE}.partial.$$${EXT}"   # keeps the real extension so zip/rar don't rename it

log "creating $FMT archive with $COUNT entries"

case "$FMT" in
  tgz|bzip)
    need_cmd tar
    cmd=(tar -c -f "$PARTIAL")
    if [[ $FMT == tgz ]]; then need_cmd gzip;  cmd+=(-z); else need_cmd bzip2; cmd+=(-j); fi
    if (( SYMCOPY ));  then cmd+=(-h); fi
    if (( VERBOSE ));  then cmd+=(-v); fi
    cmd+=(--null --no-recursion -T "$FINAL")
    "${cmd[@]}"
    ;;
  zip|rar)
    # zip and rar read newline-separated lists
    NL=$(( $(tr -cd '\n' < "$FINAL" | wc -c) ))
    (( NL == 0 )) || die "file names containing newlines are not supported with $FMT"
    TXT=$(mktemp "${TMPDIR:-/tmp}/ubuu.txt.XXXXXX")
    tr '\0' '\n' < "$FINAL" > "$TXT"

    if [[ $FMT == zip ]]; then
      need_cmd zip
      cmd=(zip -nw)
      if (( ! SYMCOPY )); then cmd+=(-y); fi      # -y = store symlinks as links
      if (( ! VERBOSE )); then cmd+=(-q); fi
      cmd+=("$PARTIAL" -@)
      "${cmd[@]}" < "$TXT"
    else
      need_cmd rar
      cmd=(rar a -r-)                             # list already contains every entry
      if (( ! SYMCOPY )); then cmd+=(-ol); fi     # -ol = store symlinks as links
      if (( ! VERBOSE )); then cmd+=(-idq); fi
      cmd+=("$PARTIAL" "@$TXT")
      "${cmd[@]}"
    fi
    ;;
esac

[[ -s $PARTIAL ]] || die "archive was not created"

# ---------- encrypt (optional) and move into place ----------
if (( ENCRYPT )); then
  ENCPART="${PARTIAL}.enc"
  log "encrypting with $ENC_ALGO"
  encrypt_file "$PARTIAL" "$ENCPART"
  PASSWORD=""
  rm -f -- "$PARTIAL"; PARTIAL=""             # remove the unencrypted archive
  [[ -s $ENCPART ]] || die "encryption failed"
  mv -f -- "$ENCPART" "$OUT_FINAL"
  ENCPART=""
else
  mv -f -- "$PARTIAL" "$OUT_FINAL"
  PARTIAL=""
fi

SIZE=$(du -h -- "$OUT_FINAL" | cut -f1)
printf 'Backup created: %s (%s, %d entries)\n' "$OUT_FINAL" "$SIZE" "$COUNT"
if (( ENCRYPT )); then
  printf 'Decrypt with:   openssl enc -d -%s -pbkdf2 -iter 600000 -in %q -out %q\n' \
    "$ENC_ALGO" "$OUT_FINAL" "${OUT_FINAL%.enc}"
fi

