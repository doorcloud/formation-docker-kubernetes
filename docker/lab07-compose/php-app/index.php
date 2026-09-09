<?php
declare(strict_types=1);

header('Content-Type: text/html; charset=UTF-8');

$host = getenv('MYSQL_HOST') ?: 'mysql';
$db   = getenv('MYSQL_DATABASE') ?: 'appdb';
$user = getenv('MYSQL_USER') ?: 'appuser';
$pass = getenv('MYSQL_PASSWORD') ?: 'ChangeMe-app';
$hostname = gethostname() ?: 'inconnu';

try {
    $pdo = new PDO(
        sprintf('mysql:host=%s;dbname=%s;charset=utf8mb4', $host, $db),
        $user,
        $pass,
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_TIMEOUT => 3,
        ]
    );
    $row = $pdo->query('SELECT NOW() AS t')->fetch(PDO::FETCH_ASSOC);
    $mysqlNow = $row['t'] ?? 'n/a';
    $phpNow = date('Y-m-d H:i:s');
} catch (PDOException $e) {
    http_response_code(500);
    echo '<!DOCTYPE html><html lang="fr"><head><meta charset="UTF-8"><title>Erreur MySQL</title></head><body>';
    echo '<h1>Connexion MySQL impossible</h1>';
    echo '<p>' . htmlspecialchars($e->getMessage(), ENT_QUOTES, 'UTF-8') . '</p>';
    echo '</body></html>';
    exit;
}

http_response_code(200);
?>
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <title>Lab 07 — Compose</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 42rem; margin: 3rem auto; color: #0f172a; }
    h1 { color: #2563eb; }
    code { background: #f1f5f9; padding: 0.15rem 0.4rem; border-radius: 4px; }
    dl { display: grid; grid-template-columns: 10rem 1fr; gap: 0.4rem 1rem; }
  </style>
</head>
<body>
  <h1>Connexion MySQL réussie</h1>
  <p>La pile <strong>nginx + php-fpm + mysql</strong> communique sur le réseau Compose.</p>
  <dl>
    <dt>Heure PHP</dt><dd><code><?= htmlspecialchars($phpNow, ENT_QUOTES, 'UTF-8') ?></code></dd>
    <dt>Heure MySQL</dt><dd><code><?= htmlspecialchars($mysqlNow, ENT_QUOTES, 'UTF-8') ?></code></dd>
    <dt>Hostname PHP</dt><dd><code><?= htmlspecialchars($hostname, ENT_QUOTES, 'UTF-8') ?></code></dd>
  </dl>
</body>
</html>
