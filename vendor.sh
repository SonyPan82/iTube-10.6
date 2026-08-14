#!/bin/bash
# vendor.sh
#
# Recupere une version de yt-dlp et un binaire ffmpeg statique compatibles
# avec une plage de compatibilite tres large (Snow Leopard 10.6 -> Mavericks
# 10.9), et les place dans Xcode/Resources/Tools pour etre ajoutes au bundle
# de l'application dans Xcode (Build Phases > Copy Bundle Resources, en
# gardant la structure de dossier "Tools").
#
# IMPORTANT - a lire avant de lancer ce script :
#
#   yt-dlp evolue en permanence pour suivre les changements cote YouTube -
#   une version figee finit toujours par se faire rejeter ("The following
#   content is not available on this app.. Watch on the latest version of
#   YouTube."), generalement en quelques mois. Ce script recupere donc la
#   DERNIERE release de yt-dlp (--dernier tag GitHub), ce qui exige Python
#   3.10+. Sur Snow Leopard/Mavericks, ca veut dire qu'il faut d'abord avoir
#   fait tourner Scripts/build-legacy-python.sh (Python 3.11 compile depuis
#   les sources, cible 10.6) - voir ce script et Docs/ARCHITECTURE.md.
#
#   Sans Tools/Python3.11 deja present, YTDLPController se rabat sur un
#   Python 3.6 (python.org, 10.6+) trop ancien pour n'importe quelle
#   release de yt-dlp recente : l'app tournera mais la recherche/le
#   telechargement echoueront. Executez build-legacy-python.sh D'ABORD.
#
# Usage:
#   ./Scripts/build-legacy-python.sh   # sur un Mac Intel (voir ce script)
#   chmod +x vendor.sh
#   ./vendor.sh
#
# Resultat:
#   Tools/yt-dlp                (script Python, PAS un binaire autonome)
#   Tools/ffmpeg                (binaire statique)
#   Tools/cacert.pem            (bundle de certificats racine)
#   Tools/Python3.11/...        (si build-legacy-python.sh a deja tourne)
#   Tools/Python.framework/...  (repli Python 3.6, insuffisant a lui seul)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="${SCRIPT_DIR}/Tools"

# "latest" recupere le dernier tag publie sur GitHub. Ne PAS figer cette
# version sur le long terme : yt-dlp casse regulierement face a YouTube,
# donc revenez lancer vendor.sh periodiquement pour rester a jour.
YTDLP_VERSION="$(curl -fsSL https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')"
if [ -z "$YTDLP_VERSION" ]; then
    echo "Impossible de determiner la derniere version de yt-dlp (rate limit GitHub API ?)." >&2
    echo "Fixez YTDLP_VERSION manuellement dans ce script pour reessayer." >&2
    exit 1
fi
echo "yt-dlp: derniere version = ${YTDLP_VERSION}"

echo "== iTube vendor.sh =="
mkdir -p "${TOOLS_DIR}"

# --- 1. yt-dlp (script Python unique, pas de binaire autonome) ------------
echo "-> Telechargement de yt-dlp ${YTDLP_VERSION} (script Python)"
curl -L -o "${TOOLS_DIR}/yt-dlp" \
  "https://github.com/yt-dlp/yt-dlp/releases/download/${YTDLP_VERSION}/yt-dlp"
chmod +x "${TOOLS_DIR}/yt-dlp"

# --- 2. ffmpeg statique legacy ---------------------------------------------
# Aucun binaire ffmpeg pret-a-l'emploi ne cible correctement 10.6 (evermeet.cx
# ne publie que des builds recents). Utilisez Scripts/build-legacy-ffmpeg.sh
# a la place, qui compile ffmpeg+ffprobe depuis les sources (libmp3lame pour
# l'encodage MP3, decodeurs natifs AAC/Opus/Vorbis pour lire les flux
# YouTube) avec -mmacosx-version-min=10.6. Contrairement au Python de
# l'etape 3, ce build fonctionne tel quel sur Apple Silicon (pas d'execution
# du binaire cible en cours de compilation).
if [ ! -f "${TOOLS_DIR}/ffmpeg" ]; then
    echo "-> ffmpeg absent : lancez ./Scripts/build-legacy-ffmpeg.sh avant de continuer."
fi

# --- 2bis. Bundle de certificats racine ------------------------------------
# Les interpreteurs Python vendorises (etape 3) n'embarquent aucun certificat
# racine (contrairement au Trousseau macOS) -> sans ca, toute requete HTTPS
# echoue avec CERTIFICATE_VERIFY_FAILED, meme vers des sites legitimes.
echo "-> Telechargement du bundle de certificats racine (Mozilla, via curl.se)"
curl -L -o "${TOOLS_DIR}/cacert.pem" "https://curl.se/ca/cacert.pem"

# --- 3. Python -------------------------------------------------------------
# yt-dlp "latest" (etape 1) exige Python 3.10+. Lancez d'abord :
#   ./Scripts/build-legacy-python.sh
# sur un Mac Intel (ou un runner CI Intel) - ca produit Tools/Python3.11/,
# un Python 3.11 + OpenSSL compiles depuis les sources avec
# -mmacosx-version-min=10.6, donc a la fois assez recent pour yt-dlp et
# lancable sur Snow Leopard. YTDLPController le detecte automatiquement.
#
# Repli (deconseille, yt-dlp recent ne fonctionnera pas dessus) : un Python
# 3.6.8 installe depuis python.org (installeur "macOS 64-bit/32-bit
# installer", 10.6+) puis copie a la main :
#   cp -R /Library/Frameworks/Python.framework "${TOOLS_DIR}/Python.framework"

if [ -d "${TOOLS_DIR}/Python3.11" ]; then
    echo "-> Tools/Python3.11 present : verification avec yt-dlp ${YTDLP_VERSION}"
    "${TOOLS_DIR}/Python3.11/bin/python3.11" "${TOOLS_DIR}/yt-dlp" --version || true
else
    echo ""
    echo "ATTENTION : Tools/Python3.11 est absent. yt-dlp ${YTDLP_VERSION} ne"
    echo "fonctionnera PAS sous le Python 3.6 de secours (trop ancien). Lancez :"
    echo "  ./Scripts/build-legacy-python.sh"
    echo "sur un Mac Intel, puis relancez ./vendor.sh."
fi

echo ""
echo "Termine. Voir Docs/ARCHITECTURE.md pour le detail de chaque piece."
