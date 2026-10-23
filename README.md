# Sondages présidentielles 2017 / 2022 / 2027

Outil interactif pour suivre les sondages de la présidentielle 2027 et les comparer, à date équivalente, avec ceux de 2022 et 2017.

**En ligne : https://hugoc1.github.io/sondages_presidentielles/**

## Utilisation

- En ligne : le lien ci-dessus, mis à jour automatiquement chaque matin.
- En local : ouvrir **`index.html`** dans un navigateur (double-clic). Fonctionne hors ligne (Plotly est dans `lib/`).
- **Mettre à jour la copie locale** : double-cliquer sur `mettre_a_jour.bat`. Il récupère les données extraites par GitHub (`git pull`) ; sans accès à GitHub, il lance l'extraction en local avec R.

## Mise à jour automatique (GitHub Actions)

Le fichier `.github/workflows/mise_a_jour.yml` tourne chaque jour vers 6-7 h (heure de Paris), à chaque push sur `main`, et à la demande (onglet *Actions* → *Mise à jour des sondages* → *Run workflow*). Il :

1. installe R et les packages `rvest`, `xml2`, `jsonlite` ;
2. lance `scripts/parse_wikipedia.R` (téléchargement des 3 pages + extraction) ;
3. enregistre les données dans le dépôt si elles ont changé ;
4. publie la page sur GitHub Pages.

Si l'extraction échoue (Wikipédia indisponible, tableaux modifiés), rien n'est publié : la page en ligne garde les dernières données valides et GitHub envoie un e-mail. GitHub peut suspendre les tâches planifiées d'un dépôt resté 60 jours sans activité : les réactiver depuis l'onglet *Actions*.

## Fonctionnalités

- Choix des candidats par élection (pastilles à gauche) + préréglages (Le Pen ×3, Mélenchon ×3, bloc central, droite LR…).
- Axe du temps : **jours avant le 1er tour** (pour superposer les campagnes) ou **calendrier réel**.
- 1er tour et 2nd tour (duels testés).
- Lissage par moyenne mobile (noyau gaussien, fenêtre 15 à 120 j) ou sondages reliés.
- Hypothèses : moyenne par sondage (défaut, évite de surpondérer les instituts qui testent beaucoup d'hypothèses) ou toutes les hypothèses.
- Infobulle sur chaque point : institut, dates de terrain, échantillon, score, composition de l'hypothèse.
- ★ = résultat officiel. Trait plein = 2027, tirets = 2022, pointillés = 2017.
- Tableau « comparaison à date équivalente » : moyenne de chaque série au même nombre de jours avant le scrutin qu'aujourd'hui pour 2027.

## Arborescence

| Chemin | Contenu |
|---|---|
| `index.html` | la page interactive |
| `data/sondages_1er_tour.csv`, `data/sondages_2nd_tour.csv` | données extraites, format long (1 ligne = 1 candidat × 1 hypothèse) |
| `data/sondages.js` | les mêmes données, compactées pour la page |
| `data/raw/wiki_AAAA.html` | pages Wikipédia brutes (non versionnées) |
| `scripts/parse_wikipedia.R` | téléchargement + extraction (`--offline` pour réutiliser `data/raw/`) |
| `.github/workflows/mise_a_jour.yml` | tâche quotidienne GitHub (extraction + publication) |
| `mettre_a_jour.bat` | met à jour la copie locale |

## Notes sur l'extraction

- Dates : on retient la **date de fin de terrain**. L'année manquante est déduite du titre de section ou de la légende du tableau (2017).
- Une cellule du type « 10 Hollande (PS) » est attribuée au candidat cité (et non à celui de la colonne).
- « <1 » est codé 0,5.
- Sont exclus : rollings quotidiens (2022), estimations du soir du 1er tour, reports de voix, section « Autres » (2027).
- Les intitulés génériques (« Candidat RN », « Candidat LR »…) sont gardés tels quels, distincts des candidats nommés.
- Dates des scrutins : 23/04/2017, 10/04/2022, 18/04/2027 (1er tour).

Source : Wikipédia (CC BY-SA).
