sudo lpadmin -x lp1 2>/dev/null || true
sudo lpadmin -x lp2 2>/dev/null || true

sudo lpadmin -p lp1 -E \
  -v cups-pdf:/ \
  -P /usr/share/ppd/cups-pdf/CUPS-PDF_opt.ppd \
  -D "CUPS-PDF A4" \
  -o PageSize=A4

sudo lpadmin -p lp2 -E \
  -v cups-pdf:/ \
  -P /usr/share/ppd/cups-pdf/CUPS-PDF_opt.ppd \
  -D "CUPS-PDF A5" \
  -o PageSize=A5
