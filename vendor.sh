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
#   yt-dlp moderne exige Python 3.9+. Il n'y a AUCUNE version officielle de
#   yt-dlp compatible nativement avec le Python 2.6/2.7 fourni par Snow
#   Leopard/Mavericks. La strategie retenue ici est de vendoriser :
#
#     1. Un interpreteur Python 3.6 portable (derniere branche Python encore
#        installable via un installeur python.org supportant "Mac OS X
#        10.6+"), et
#     2. Une ANCIENNE release de yt-dlp (fixee ci-dessous) encore compatible
#        Python 3.6.
#
#   Il n'existe pas de garantie absolue que telle ou telle vieille release
#   fonctionne sans accroc sur du vrai materiel/VM 10.6-10.9 : le seul moyen
#   fiable de le confirmer est de tester. Ce script pose les bases ; ajustez
#   YTDLP_VERSION plus bas si necessaire (voir la section "Si ca ne marche
#   pas" en fin de fichier).
#
# Usage:
#   chmod +x vendor.sh
#   ./vendor.sh
#
# Resultat:
#   Tools/yt-dlp                (script Python, PAS un binaire autonome)
#   Tools/ffmpeg                (binaire statique)
#   Tools/Python.framework/...  (interpreteur Python 3.6 portable)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="${SCRIPT_DIR}/Tools"

# Derniere release de yt-dlp connue pour fonctionner sous Python 3.6.
# yt-dlp a releve son minimum a Python 3.7 courant 2023 ; en dessous de
# cette version, cette contrainte n'existait pas encore.
YTDLP_VERSION="2022.05.18"

echo "== iTube vendor.sh =="
mkdir -p "${TOOLS_DIR}"

# --- 1. yt-dlp (script Python unique, pas de binaire autonome) ------------
echo "-> Telechargement de yt-dlp ${YTDLP_VERSION} (script Python)"
curl -L -o "${TOOLS_DIR}/yt-dlp" \
  "https://github.com/yt-dlp/yt-dlp/releases/download/${YTDLP_VERSION}/yt-dlp"
chmod +x "${TOOLS_DIR}/yt-dlp"

# --- 2. ffmpeg statique legacy ---------------------------------------------
# evermeet.cx conserve un historique de builds ffmpeg statiques pour macOS,
# y compris d'anciennes versions ciblant des OS plus vieux. Verifiez sur
# https://evermeet.cx/ffmpeg/ quelle archive correspond a une compilation
# compatible 10.6/10.9 (regarder la colonne "OS X") et ajustez l'URL
# ci-dessous en consequence -- le lien "current" pointe vers le dernier
# build (probablement trop recent pour 10.6).
echo "-> Telechargement de ffmpeg (verifiez la compatibilite sur evermeet.cx/ffmpeg)"
curl -L -o "${TOOLS_DIR}/ffmpeg.zip" "https://evermeet.cx/ffmpeg/getrelease/zip"
unzip -o "${TOOLS_DIR}/ffmpeg.zip" -d "${TOOLS_DIR}"
rm "${TOOLS_DIR}/ffmpeg.zip"
chmod +x "${TOOLS_DIR}/ffmpeg"

# --- 3. Python 3.6 portable -------------------------------------------------
# Le moyen le plus fiable est d'installer officiellement Python 3.6.8 depuis
# python.org (installeur "macOS 64-bit/32-bit installer", qui annonce le
# support 10.6+) sur une machine de build, PUIS de copier le framework
# resultant ici. Ce script ne peut pas le faire automatiquement (installeur
# .pkg interactif), d'ou les etapes manuelles :
#
#   1. Telecharger et installer :
#      https://www.python.org/ftp/python/3.6.8/python-3.6.8-macosx10.6.pkg
#   2. Copier le framework installe dans le projet :
#      cp -R /Library/Frameworks/Python.framework "${TOOLS_DIR}/Python.framework"
#   3. Verifier que l'interpreteur qui sera bundle est bien autonome (pas de
#      dependance a un chemin absolu hors du bundle) :
#      otool -L "${TOOLS_DIR}/Python.framework/Versions/3.6/bin/python3"
#
# Une fois ces 3 etapes faites a la main, YTDLPController resoudra
# automatiquement ce chemin via +[YTDLPController bundledPythonPath].

echo ""
echo "Termine (etapes 1 et 2). N'oubliez pas l'etape manuelle 3 : installer"
echo "Python 3.6.8 (python.org, installeur 10.6+) et copier son framework"
echo "dans ${TOOLS_DIR}/Python.framework -- voir les commentaires de ce script."
echo ""
echo "Verification recommandee (sur la machine de build, avant de figer les"
echo "binaires vendorises) :"
echo "  ${TOOLS_DIR}/Python.framework/Versions/3.6/bin/python3 ${TOOLS_DIR}/yt-dlp --version"
echo ""
echo "Si ca ne marche pas :"
echo "  - Si yt-dlp ${YTDLP_VERSION} refuse de se lancer sous Python 3.6, essayez"
echo "    une release plus ancienne (baissez YTDLP_VERSION dans ce script -- la"
echo "    liste complete est sur https://github.com/yt-dlp/yt-dlp/releases)."
echo "  - Si le ffmpeg telecharge ne se lance pas sur la machine cible (10.6-10.9),"
echo "    cherchez un build ffmpeg plus ancien/statique 32-bit sur evermeet.cx"
echo "    ou compilez-le vous-meme avec -mmacosx-version-min=10.6."
