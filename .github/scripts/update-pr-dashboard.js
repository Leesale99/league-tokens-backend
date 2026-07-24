module.exports = async function({ github, context }) {
  const needsData = JSON.parse(process.env.NEEDS_DATA);
  const runUrl = `https://github.com/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId}`;
  const prNumber = parseInt(process.env.PR_NUMBER, 10);

  const reviews = [
    { name: 'Quality', key: 'quality' },
    { name: 'Correctness', key: 'correctness' },
    { name: 'Security', key: 'security' },
    { name: 'Quality-Depth', key: 'quality-depth' },
  ];

  const icon = (r) => {
    if (r === 'success') return '✅';
    if (r === 'failure') return '❌';
    if (r === 'cancelled') return '🚫';
    return '⏳';
  };

  let table = '\n\n## CI Review Status\n\n';
  table += '| Review | Status |\n|--------|--------|\n';
  for (const r of reviews) {
    const result = needsData[r.key]?.result || 'skipped';
    table += `| ${r.name} | ${icon(result)} ${result} |\n`;
  }
  table += `\n[View workflow run](${runUrl})\n`;

  const { data: pr } = await github.rest.pulls.get({
    owner: context.repo.owner,
    repo: context.repo.repo,
    pull_number: prNumber,
  });

  let body = pr.body || '';
  body = body.replace(/\n\n## CI Review Status[\s\S]*$/g, '');
  body += table;

  await github.rest.pulls.update({
    owner: context.repo.owner,
    repo: context.repo.repo,
    pull_number: prNumber,
    body,
  });
};