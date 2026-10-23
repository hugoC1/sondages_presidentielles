@echo off
REM Recupere les dernieres donnees (extraites chaque jour par GitHub).
REM En cas d'echec (pas de reseau GitHub), extrait localement depuis Wikipedia.
cd /d "%~dp0"
echo Recuperation des dernieres donnees depuis GitHub...
git checkout -- data 2>nul
git pull --ff-only
if errorlevel 1 (
  echo.
  echo Echec de la recuperation GitHub : extraction locale depuis Wikipedia...
  "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" scripts\parse_wikipedia.R
)
echo.
echo Termine. Rechargez index.html dans le navigateur.
pause
