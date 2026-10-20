/**
 * Release notes as HTML. They are Markdown in the shape
 * scripts/release-notes.py checks: `###` headings, `-` bullets and
 * paragraphs, nothing else, so this is all the Markdown they need.
 */
export function notesHTML(markdown: string): string {
  const html: string[] = [];
  let list: string[] = [];
  const flush = () => {
    if (list.length) html.push(`<ul>${list.map((item) => `<li>${item}</li>`).join('')}</ul>`);
    list = [];
  };
  for (const line of markdown.split('\n').map((line) => line.trim())) {
    if (line.startsWith('- ')) {
      list.push(escape(line.slice(2)));
      continue;
    }
    flush();
    if (line.startsWith('### ')) html.push(`<h3>${escape(line.slice(4))}</h3>`);
    else if (line) html.push(`<p>${escape(line)}</p>`);
  }
  flush();
  return html.join('\n');
}

function escape(text: string): string {
  return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}
