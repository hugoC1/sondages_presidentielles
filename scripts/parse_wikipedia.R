# -----------------------------------------------------------------------------
# Sondages présidentielles 2017 / 2022 / 2027 - extraction depuis Wikipédia
#
# Usage :  Rscript scripts/parse_wikipedia.R            (re-télécharge les pages)
#          Rscript scripts/parse_wikipedia.R --offline  (réutilise data/raw/)
#
# Sorties : data/sondages_1er_tour.csv, data/sondages_2nd_tour.csv (format long)
#           data/sondages.js (données pour index.html)
# -----------------------------------------------------------------------------
suppressPackageStartupMessages({
  library(rvest); library(xml2); library(jsonlite)
})

args <- commandArgs(TRUE)
offline <- "--offline" %in% args

# Dossier racine du projet = parent du dossier du script
script_path <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
root <- if (length(script_path)) normalizePath(file.path(dirname(script_path), "..")) else getwd()
raw_dir <- file.path(root, "data", "raw")
dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)

elections <- data.frame(
  annee  = c(2017, 2022, 2027),
  tour1  = as.Date(c("2017-04-23", "2022-04-10", "2027-04-18")),
  tour2  = as.Date(c("2017-05-07", "2022-04-24", "2027-05-02"))
)

url_of <- function(y) sprintf(
  "https://fr.wikipedia.org/wiki/Liste_de_sondages_sur_l%%27%%C3%%A9lection_pr%%C3%%A9sidentielle_fran%%C3%%A7aise_de_%d", y)

# --- Téléchargement ----------------------------------------------------------
for (y in elections$annee) {
  f <- file.path(raw_dir, sprintf("wiki_%d.html", y))
  if (!offline || !file.exists(f)) {
    message("Téléchargement ", y, " ...")
    download.file(url_of(y), f, quiet = TRUE, mode = "wb",
                  headers = c("User-Agent" = "sondages-presidentielles/0.1 (https://github.com/hugoC1/sondages_presidentielles)"))
  }
}

# --- Outils ------------------------------------------------------------------
clean_txt <- function(x) {
  x <- gsub("\\[[^]]*\\]", "", x)          # appels de notes [a], [N 3]
  x <- gsub("[   ]", " ", x) # espaces insécables
  x <- gsub("\\s+", " ", x)
  trimws(x)
}

mois <- c(janvier = 1, janv = 1, jan = 1, "février" = 2, "févr" = 2, "fév" = 2, fevrier = 2,
          mars = 3, avril = 4, avr = 4, mai = 5, juin = 6, juillet = 7, juil = 7,
          "août" = 8, aout = 8, septembre = 9, sept = 9, sep = 9, octobre = 10, oct = 10,
          novembre = 11, nov = 11, "décembre" = 12, "déc" = 12, decembre = 12, dec = 12)
mois_re <- paste0("(", paste(names(mois)[order(-nchar(names(mois)))], collapse = "|"), ")")

# Renvoie list(day, month, year) de la DERNIÈRE date citée (fin de terrain)
parse_date_txt <- function(x) {
  x <- tolower(clean_txt(x))
  re <- paste0("(\\d{1,2})?\\s*(?:er)?\\s*", mois_re, "\\.?(?:\\s*(\\d{4}))?")
  m <- regmatches(x, gregexpr(re, x, perl = TRUE))[[1]]
  if (!length(m)) return(NULL)
  last <- m[length(m)]
  p <- regmatches(last, regexec(re, last, perl = TRUE))[[1]]
  yrs <- regmatches(x, gregexpr("\\d{4}", x))[[1]]
  list(day = if (nzchar(p[2])) as.integer(p[2]) else 15L,
       month = unname(mois[p[3]]),
       year = if (length(yrs)) as.integer(yrs[length(yrs)]) else NA_integer_)
}

# Valeur d'une cellule : nombre + éventuel candidat de remplacement ("10 Hollande (PS)")
parse_value <- function(x) {
  x <- clean_txt(x)
  if (!nzchar(x) || grepl("^[—–-]+$", x)) return(NULL)
  m <- regmatches(x, regexec("^(<|&lt;)?\\s*(\\d+(?:[,.]\\d+)?)\\s*%?\\s*(.*)$", x))[[1]]
  if (!length(m)) return(NULL)
  v <- as.numeric(sub(",", ".", m[3]))
  if (nzchar(m[2])) v <- 0.5               # "<1" -> 0,5
  rest <- trimws(gsub("^[()%\\s]+|[()\\s]+$", "", m[4]))
  alt <- NULL
  if (grepl("\\d", rest)) return(NULL)      # cellule à double valeur ("Bertrand 8 % Pécresse ...")
  if (grepl("[[:alpha:]]", rest)) {
    a <- regmatches(m[4], regexec("^\\s*([^(]+?)\\s*(?:\\(([^)]+)\\))?\\s*$", m[4]))[[1]]
    if (length(a)) alt <- list(name = trimws(a[2]), party = if (nzchar(a[3])) a[3] else NA)
  }
  list(v = v, alt = alt)
}

split_name_party <- function(txt, election) {
  txt <- clean_txt(txt)
  m <- regmatches(txt, regexec("^(.*?)\\s*\\(([^()]+)\\)\\s*$", txt))[[1]]
  if (length(m)) { name <- m[2]; party <- m[3] } else { name <- txt; party <- NA }
  name <- trimws(name)
  if (is.na(party) && grepl("^Candidat", name)) party <- trimws(sub("^Candidats?\\s*", "", name))
  if (grepl("^Candidat", name)) name <- paste("Candidat", gsub("\\s*/\\s*", "/", party))
  # 2017 : prénom + nom -> nom seul (cohérent avec 2022/2027)
  if (election == 2017 && !grepl("^Candidat", name) && grepl(" ", name)) name <- sub("^\\S+\\s+", "", name)
  list(name = name, party = party)
}

# Développe un tableau HTML (rowspan / colspan) en grille
expand_table <- function(tbl) {
  rows <- html_elements(tbl, xpath = "./tbody/tr | ./tr | ./thead/tr")
  n <- length(rows)
  ncol_max <- 80
  ID <- matrix(NA_integer_, n, ncol_max)
  cells <- list(); k <- 0
  for (i in seq_len(n)) {
    j <- 1
    for (c in html_elements(rows[[i]], xpath = "./th | ./td")) {
      while (j <= ncol_max && !is.na(ID[i, j])) j <- j + 1
      rs <- suppressWarnings(as.integer(xml_attr(c, "rowspan"))); if (is.na(rs) || rs < 1) rs <- 1
      cs <- suppressWarnings(as.integer(xml_attr(c, "colspan"))); if (is.na(cs) || cs < 1) cs <- 1
      k <- k + 1
      cells[[k]] <- list(node = c, th = xml_name(c) == "th", txt = html_text2(c), rs = rs, cs = cs)
      ri <- i:min(n, i + rs - 1); ci <- j:min(ncol_max, j + cs - 1)
      ID[ri, ci] <- k
      j <- j + cs
    }
  }
  used <- which(colSums(!is.na(ID)) > 0)
  list(ID = ID[, seq_len(max(used)), drop = FALSE], cells = cells)
}

# --- Parcours d'une page -----------------------------------------------------
parse_page <- function(y) {
  doc <- read_html(file.path(raw_dir, sprintf("wiki_%d.html", y)))
  el <- elections[elections$annee == y, ]
  nodes <- html_elements(doc, xpath = paste(
    "//div[contains(@class,'mw-heading')]/*[self::h2 or self::h3 or self::h4]",
    "| //table[contains(@class,'wikitable')]"))
  h <- c(h2 = "", h3 = "", h4 = "")
  out <- list(); ti <- 0
  for (nd in nodes) {
    nm <- xml_name(nd)
    if (nm != "table") {
      h[nm] <- clean_txt(html_text2(nd))
      if (nm == "h2") h[c("h3", "h4")] <- ""
      if (nm == "h3") h["h4"] <- ""
      next
    }
    ti <- ti + 1
    tour <- if (grepl("premier tour", h["h2"], ignore.case = TRUE)) 1L else
            if (grepl("second tour", h["h2"], ignore.case = TRUE)) 2L else NA
    if (is.na(tour)) next
    if (any(grepl("rolling|estimation|reports? de voix|^autres$|synth[eè]se", h[2:3], ignore.case = TRUE))) next
    section <- paste(h[nzchar(h)], collapse = " > ")
    res <- parse_table(nd, y, el, tour, section, ti, h)
    if (!is.null(res)) out[[length(out) + 1]] <- res
  }
  do.call(rbind, out)
}

parse_table <- function(tbl, y, el, tour, section, ti, h) {
  g <- expand_table(tbl); ID <- g$ID; cells <- g$cells
  first <- cells[[ID[1, 1]]]
  nh <- if (first$th) first$rs else 1
  if (nh < 2) nh <- 2
  nc <- ncol(ID)
  lab <- character(nc); hdr_cell <- integer(nc)
  for (j in seq_len(nc)) {
    ids <- unique(na.omit(ID[seq_len(nh), j]))
    txts <- vapply(ids, function(k) clean_txt(cells[[k]]$txt), "")
    keep <- nzchar(txts)
    lab[j] <- if (any(keep)) tail(txts[keep], 1) else ""
    hdr_cell[j] <- if (any(keep)) tail(ids[keep], 1) else NA
  }
  low <- tolower(lab)
  col_sond <- which(grepl("^sondeur", low))[1]
  col_date <- which(grepl("^dates?$|^date", low))[1]
  col_ech  <- which(grepl("chantillon", low))[1]
  meta <- grepl("^sondeur|^dates?|chantillon|abstention|ind[ée]cis|autres|blanc|non.exprim|nsp|^$", low)
  cand_cols <- which(!meta)
  if (is.na(col_sond) || is.na(col_date) || !length(cand_cols)) return(NULL)

  cand_info <- lapply(cand_cols, function(j) split_name_party(cells[[hdr_cell[j]]]$txt, y))

  # Légende du tableau (2017 : "Janvier 2017" -> mois absent des cellules de date)
  cap <- clean_txt(html_text2(html_element(tbl, "caption")))
  if (is.na(cap)) cap <- ""
  cap_pd <- parse_date_txt(cap)

  # Année de départ : légende ou titre de section, sinon année de l'élection
  ctx <- paste(cap, h[3], h[2])
  yrs <- as.integer(unlist(regmatches(ctx, gregexpr("\\d{4}", ctx))))
  cur_y <- if (length(yrs)) max(yrs) else y
  if (tour == 2 && !length(yrs)) cur_y <- y
  prev_m <- NA

  recs <- list()
  for (i in seq.int(nh + 1, nrow(ID))) {
    rid <- ID[i, ]
    if (all(is.na(rid))) next
    ids <- unique(na.omit(rid))
    if (length(ids) == 1 || cells[[ids[1]]]$cs >= nc - 1) next    # ligne d'événement
    sid <- ID[i, col_sond]
    sond <- clean_txt(cells[[sid]]$txt)
    if (!nzchar(sond)) next
    is_res <- grepl("^r[ée]sultat", sond, ignore.case = TRUE)
    dt_txt <- clean_txt(cells[[ID[i, col_date]]]$txt)
    pd <- parse_date_txt(dt_txt)
    if (is.null(pd) && !is.null(cap_pd) && grepl("\\d", dt_txt)) {
      days <- as.integer(regmatches(dt_txt, gregexpr("\\d{1,2}", dt_txt))[[1]])
      pd <- list(day = tail(days, 1), month = cap_pd$month, year = cap_pd$year)
    }
    if (is_res) {
      d <- if (tour == 1) el$tour1 else el$tour2
    } else {
      if (is.null(pd)) next
      if (!is.na(pd$year)) cur_y <- pd$year
      else if (!is.na(prev_m) && pd$month > prev_m + 1) cur_y <- cur_y - 1  # on remonte le temps
      prev_m <- pd$month
      d <- as.Date(sprintf("%d-%02d-%02d", cur_y, pd$month, min(pd$day, 28L + (pd$month != 2) * 2L)))
      if (is.na(d)) next
    }
    ech <- if (!is.na(col_ech)) suppressWarnings(as.integer(gsub("\\D", "", sub("\\[.*", "", cells[[ID[i, col_ech]]]$txt)))) else NA
    seen <- integer(0)
    for (q in seq_along(cand_cols)) {
      j <- cand_cols[q]; cid <- rid[j]
      if (is.na(cid) || cid %in% seen) next
      seen <- c(seen, cid)
      pv <- parse_value(cells[[cid]]$txt)
      if (is.null(pv)) next
      ci <- cand_info[[q]]
      if (!is.null(pv$alt)) ci <- split_name_party(paste0(pv$alt$name, if (!is.na(pv$alt$party)) paste0(" (", pv$alt$party, ")")), 0)
      recs[[length(recs) + 1]] <- data.frame(
        election = y, tour = tour, section = section, tableau = ti,
        sondage_id = sprintf("%d-%d-%d-%d", y, tour, ti, sid), ligne = i,
        sondeur = sond, dates_terrain = dt_txt, date = d, echantillon = ech,
        resultat = is_res, candidat = ci$name, parti = ci$party, score = pv$v,
        stringsAsFactors = FALSE)
    }
  }
  if (!length(recs)) return(NULL)
  df <- do.call(rbind, recs)
  df$hypothese_id <- paste(df$sondage_id, df$ligne, sep = "-")
  df
}

# --- Exécution ---------------------------------------------------------------
all <- do.call(rbind, lapply(elections$annee, function(y) { message("Analyse ", y); parse_page(y) }))
all <- merge(all, elections, by.x = "election", by.y = "annee")
all$jours_avant_t1 <- as.integer(all$tour1 - all$date)
# garde-fous : dates incohérentes
bad <- all$date > all$tour2 | all$jours_avant_t1 > 365 * 6
if (any(bad)) { message(sum(bad), " lignes écartées (date incohérente)"); print(unique(all[bad, c("election","sondeur","dates_terrain","date")])) }
all <- all[!bad, ]
all$sondeur <- sub("^Harris Interr?active$", "Harris Interactive", all$sondeur)
# remplace "Harris" seul (même institut)
all$sondeur[all$sondeur == "Harris"] <- "Harris Interactive"
all <- all[!grepl("^(1er|premier) tour", all$sondeur, ignore.case = TRUE), ]
all <- all[order(all$election, all$tour, all$date), ]

t1 <- all[all$tour == 1, ]; t2 <- all[all$tour == 2, ]
# Duel du 2nd tour = les 2 candidats de l'hypothèse
duel <- tapply(t2$candidat, t2$hypothese_id, function(x) paste(sort(unique(x)), collapse = " – "))
t2$duel <- unname(duel[t2$hypothese_id])

cols <- c("election","tour","section","sondage_id","hypothese_id","sondeur","dates_terrain","date",
          "jours_avant_t1","echantillon","resultat","candidat","parti","score")
write.csv(t1[, cols], file.path(root, "data", "sondages_1er_tour.csv"), row.names = FALSE, fileEncoding = "UTF-8")
write.csv(t2[, c(cols, "duel")], file.path(root, "data", "sondages_2nd_tour.csv"), row.names = FALSE, fileEncoding = "UTF-8")

# --- Export JS compact pour la page -------------------------------------------
to_hyps <- function(df) {
  sp <- split(df, df$hypothese_id)
  unname(lapply(sp, function(d) list(
    e = d$election[1], s = d$sondeur[1], t = d$dates_terrain[1], d = format(d$date[1]),
    j = d$jours_avant_t1[1], n = d$echantillon[1],
    r = isTRUE(d$resultat[1]), p = d$sondage_id[1],
    v = as.list(setNames(d$score, d$candidat)))))
}
partis <- aggregate(parti ~ election + candidat, data = all[!is.na(all$parti), ],
                    FUN = function(x) names(sort(table(x), decreasing = TRUE))[1])
js <- list(
  maj = format(Sys.time(), "%Y-%m-%d %H:%M"),
  elections = lapply(seq_len(nrow(elections)), function(i) list(
    annee = elections$annee[i], tour1 = format(elections$tour1[i]), tour2 = format(elections$tour2[i]))),
  partis = partis,
  t1 = to_hyps(t1), t2 = to_hyps(t2)
)
writeLines(paste0("window.SONDAGES = ", toJSON(js, auto_unbox = TRUE, dataframe = "rows", digits = NA, na = "null"), ";"),
           file.path(root, "data", "sondages.js"), useBytes = TRUE)

# --- Résumé ------------------------------------------------------------------
message("\n1er tour : ", length(unique(t1$hypothese_id)), " hypothèses / ", length(unique(t1$sondage_id)), " sondages")
print(table(t1$election))
message("2nd tour : ", length(unique(t2$hypothese_id)), " hypothèses")
print(table(t2$election))
