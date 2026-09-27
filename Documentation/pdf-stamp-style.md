# Electronic signature stamp style

The Apple renderer is the reference implementation for this shared platform style.
The visual advice asks the reader to verify the document's electronic signature.
The PDF signature, rather than the visible stamp, supplies that verification.

- Outer radius: 64 points; separator radius: 48 points. Exactly two rings.
- Strokes: 1.8 points outer, 0.9 points separator. Red RGB: 0.7765, 0.1569, 0.1569.
- Font: Helvetica Bold, matching the PDF appearance's Helvetica-Bold resource.
- Center: four lines, with the command on its own line. All four lines use
  one shared size per locale, preferably 9 points. Fit the entire block uniformly
  to 82% of the inner diameter using the widest line's visible glyph bounds. Center individual
  lines horizontally and their combined ink bounds vertically. Use a 4-point
  gap between visible line bounds. Disable kerning to match PDF Tj advances.
- Border: 4.8-point type, over 156 degrees of each semicircle. Position glyphs
  by measured advances, spreading remaining space evenly between characters.
  The baseline differs for the two arcs so their visible glyph bounds are
  centered on radius 56. Side separators are filled dots of radius 0.55.
- EN center: CHECK / DOCUMENT / ELECTRONIC / SIGNATURE; FI above, SV below.
- FI center: TARKASTA / ASIAKIRJAN / SÄHKÖINEN / ALLEKIRJOITUS; SV above, EN below.
- SV center: KONTROLLERA / DOKUMENTETS / ELEKTRONISKA / SIGNATUR; FI above, EN below.

Run `Scripts/render-stamp-samples.sh` to produce three PNGs on the Desktop from
production vector operators using Apple's PDFKit. The temporary PDFs stay under
`tmp/pdfs/`. Other platforms should match this geometry and type fitting; their
renderers have not yet been migrated.
