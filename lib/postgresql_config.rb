# lib/postgresql_config.rb
require 'open3' # Para rodar comandos externos e pegar o stderr
require 'tempfile' # Para criar arquivos temporários para o diff

module PostgreSQLConfig
  # Retorna a versão do PostgreSQL.
  def self.get_version
    output, status = Open3.capture2("psql --version")
    if status.success? && output =~ /psql \(PostgreSQL\) (\d+\.\d+)/
      $1
    else
      "Não detectado (verifique se o psql está no PATH ou se o PostgreSQL está instalado)."
    end
  rescue StandardError => e
    "Erro: #{e.message}"
  end

  # Tenta encontrar o caminho do postgresql.conf.
  # Procura em locais comuns e usa 'pg_config --sysconfdir' se disponível.
  def self.find_postgresql_conf_path
    case RUBY_PLATFORM
    when /darwin/ # macOS
      # Homebrew: /usr/local/var/postgres/postgresql.conf
      # Ou outros locais de instalação manual
      paths = [
        "/usr/local/var/postgres/postgresql.conf", # Homebrew padrão
        "/opt/homebrew/var/postgres/postgresql.conf", # Homebrew em Apple Silicon
        "/Library/PostgreSQL/*/data/postgresql.conf", # Instalador oficial
        "/etc/postgresql/*/main/postgresql.conf" # Linux-style em macOS (raro)
      ]
    when /linux/ # Ubuntu e outras distros Linux
      paths = [
        "/etc/postgresql/*/main/postgresql.conf", # Ubuntu/Debian padrão
        "/var/lib/pgsql/data/postgresql.conf", # CentOS/RHEL padrão
        "/usr/local/pgsql/data/postgresql.conf" # Instalação manual
      ]
    else
      return "Não encontrado (SO não suportado para localização automática)"
    end

    # Tenta usar pg_config --sysconfdir
    pg_config_sysconfdir, status = Open3.capture2("pg_config --sysconfdir")
    if status.success? && !pg_config_sysconfdir.strip.empty?
      # Para Linux, sysconfdir pode ser /etc/postgresql/VERSAO/main
      # Para macOS (Homebrew), pode apontar para /usr/local/var/postgres
      if RUBY_PLATFORM =~ /linux/
        # pg_config --sysconfdir pode retornar algo como /etc/postgresql
        # Precisamos da versão e 'main'
        Dir["#{pg_config_sysconfdir.strip}/*/main/postgresql.conf"].each do |path|
          return path if File.exist?(path)
        end
      end
      # Tenta diretamente sysconfdir + postgresql.conf
      potential_path = File.join(pg_config_sysconfdir.strip, "postgresql.conf")
      return potential_path if File.exist?(potential_path)
    end

    # Verifica os caminhos predefinidos
    paths.each do |pattern|
      Dir.glob(pattern).each do |path|
        return path if File.exist?(path)
      end
    end

    "Não encontrado"
  rescue StandardError => e
    warn "Erro ao encontrar postgresql.conf: #{e.message}"
    "Erro na localização"
  end

  # Gera as alterações recomendadas para o postgresql.conf.
  # Retorna o conteúdo completo do arquivo recomendado como string.
  def self.generate_recommendations(pg_version:, disk_type:, ram_total_mb:, cpu_cores:)
    recommendations = []

    recommendations << "# Configurações geradas automaticamente em #{Time.now} por EnvironmentAnalyzer"
    recommendations << "# As recomendações abaixo são baseadas nas informações do sistema e devem ser **revisadas e ajustadas** conforme a carga de trabalho específica."
    recommendations << "# Para aplicar, substitua seu postgresql.conf existente e **reinicie o serviço do PostgreSQL**."

    # Configurações gerais
    recommendations << "\n# Configurações Gerais"
    recommendations << "listen_addresses = '*'" # Ajuste conforme sua política de segurança
    recommendations << "port = 5432" # Porta padrão
    recommendations << "max_connections = 100" # Exemplo, ajuste conforme o número esperado de conexões e recursos

    # Configurações de Recursos (ajustadas pela RAM e CPUs)
    recommendations << "\n# Configurações de Recursos"
    # shared_buffers: Geralmente 25% da RAM total, até 8GB em sistemas com muita RAM.
    shared_buffers_mb = (ram_total_mb * 0.25).to_i
    shared_buffers_mb = [shared_buffers_mb, 8192].min # Limite superior de 8GB
    recommendations << "shared_buffers = '#{shared_buffers_mb}MB'"

    # effective_cache_size: Geralmente 50-75% da RAM total. Ajuda o otimizador a estimar o cache do SO.
    effective_cache_size_mb = (ram_total_mb * 0.75).to_i
    recommendations << "effective_cache_size = '#{effective_cache_size_mb}MB'"

    # work_mem: Usada por operações de ordenação e hash em cada sessão. Cuidado para não estourar a RAM.
    # Um valor inicial conservador, pode ser ajustado para queries específicas.
    work_mem_mb = (ram_total_mb * 0.005).to_i # 0.5% da RAM por sessão
    work_mem_mb = [work_mem_mb, 16].max # Mínimo de 16MB
    recommendations << "work_mem = '#{work_mem_mb}MB'"

    # maintenance_work_mem: Para VACUUM, CREATE INDEX, ALTER TABLE. Pode ser maior.
    maintenance_work_mem_mb = (ram_total_mb * 0.1).to_i # 10% da RAM
    maintenance_work_mem_mb = [maintenance_work_mem_mb, 256].max # Mínimo de 256MB
    recommendations << "maintenance_work_mem = '#{maintenance_work_mem_mb}MB'"

    # Concorrência e Transações
    recommendations << "\n# Concorrência e Transações"
    recommendations << "max_locks_per_transaction = 256" # Aumentar se transações acessam muitos objetos
    recommendations << "max_prepared_transactions = 0" # Mantenha 0 se não usa transações preparadas (e.g., XA)
    recommendations << "wal_level = 'replica'" # Essencial para pg_badger e réplica/PITR. Não use 'minimal'.

    # Configurações de I/O e Checkpoints
    recommendations << "\n# Configurações de I/O e Checkpoints"
    # wal_buffers: 1/32 de shared_buffers, até 16MB.
    wal_buffers_mb = [(shared_buffers_mb / 32), 16].min
    wal_buffers_mb = [wal_buffers_mb, 1].max # Mínimo de 1MB
    recommendations << "wal_buffers = '#{wal_buffers_mb}MB'"

    # min_wal_size e max_wal_size: Controlam o tamanho do WAL e a frequência dos checkpoints.
    # Valores maiores resultam em menos checkpoints (menos I/O spikes), mas maior tempo de recuperação.
    recommendations << "min_wal_size = 512MB" # Aumentado para manter mais arquivos WAL
    recommendations << "max_wal_size = 4GB"   # Aumentado para reduzir a frequência de checkpoints
    recommendations << "checkpoint_timeout = 10min" # Aumentado de 5min para dar mais tempo entre checkpoints
    recommendations << "checkpoint_completion_target = 0.9" # Tenta espalhar o I/O do checkpoint ao longo do tempo

    # Configurações específicas de disco
    if disk_type == "SSD"
      recommendations << "fsync = on" # Mantenha 'on' para durabilidade.
      recommendations << "synchronous_commit = on" # Mantenha 'on' para durabilidade (o padrão). 'off' para performance com risco.
      recommendations << "full_page_writes = on" # Essencial para durabilidade.
      recommendations << "random_page_cost = 1.1" # Custo menor para SSDs (acesso aleatório mais rápido)
      recommendations << "seq_page_cost = 1.0" # Custo para acesso sequencial (geralmente 1.0)
      recommendations << "effective_io_concurrency = 200" # Maior para SSDs, indica o paralelismo de I/O
    else # HDD
      recommendations << "fsync = on"
      recommendations << "synchronous_commit = on"
      recommendations << "full_page_writes = on"
      recommendations << "random_page_cost = 4.0" # Valor padrão para HDDs
      recommendations << "seq_page_cost = 1.0"
      recommendations << "effective_io_concurrency = 2" # Menor para HDDs
    end

    # Configurações de Autovacuum
    recommendations << "\n# Configurações de Autovacuum"
    recommendations << "autovacuum = on" # Mantenha SEMPRE LIGADO em produção!
    # Número de workers: idealmente metade dos núcleos da CPU ou até 8, dependendo da carga.
    autovacuum_workers = [cpu_cores / 2, 4].max # Metade dos núcleos, mínimo 4 workers
    recommendations << "autovacuum_max_workers = #{autovacuum_workers}"
    recommendations << "autovacuum_naptime = 30s" # Reduzir para varrer mais frequentemente por tabelas
    # autovacuum_vacuum_cost_delay: Controle de I/O.
    if disk_type == "SSD"
      recommendations << "autovacuum_vacuum_cost_delay = 0ms" # Para SSDs, pode ser 0 para ser mais agressivo
    else
      recommendations << "autovacuum_vacuum_cost_delay = 2ms" # Padrão para HDDs, evita sobrecarga de I/O
    end
    recommendations << "autovacuum_vacuum_cost_limit = 1000" # Aumentar para permitir mais trabalho por varredura
    recommendations << "log_autovacuum_min_duration = 0" # Loga todas as ações do autovacuum (ótimo para monitorar)

    # Configurações de Logging para pg_badger e Monitoramento
    recommendations << "\n# Configurações de Logging para pg_badger (necessário reiniciar o PG para aplicar)"
    recommendations << "logging_collector = on"
    recommendations << "log_directory = 'pg_log'" # Diretório onde os logs serão armazenados, relativo ao data directory
    recommendations << "log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'"
    recommendations << "log_file_mode = 0600" # Permissão dos arquivos de log
    recommendations << "log_truncate_on_rotation = on" # Trunca o arquivo de log ao invés de anexar
    recommendations << "log_rotation_age = 1d" # Rotaciona diariamente
    recommendations << "log_rotation_size = 0" # Desabilita rotação por tamanho (usa rotação por idade)
    recommendations << "log_min_duration_statement = 1000" # Loga queries que demoram mais de 1 segundo (1000ms)
    # Formato de prefixo de log ESSENCIAL para pg_badger:
    recommendations << "log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,host=%h,client=%r '"
    recommendations << "log_checkpoints = on"
    recommendations << "log_connections = on"
    recommendations << "log_disconnections = on"
    recommendations << "log_lock_waits = on" # Loga quando queries esperam por locks
    recommendations << "log_temp_files = 0" # Loga arquivos temporários criados com mais de 0KB
    recommendations << "log_error_verbosity = default" # Pode ser 'terse', 'default', 'verbose'

    # Mais Configurações de Logging e Estatísticas
    recommendations << "\n# Mais Configurações de Logging e Estatísticas"
    recommendations << "log_statement = 'ddl'" # Loga apenas DDLs (CREATE, ALTER, DROP). Considere 'mod' para DMLs ou 'all' para debug.
    recommendations << "track_counts = on" # Essencial para o autovacuum e estatísticas de uso de tabelas/índices
    recommendations << "track_io_timing = on" # Útil para diagnosticar gargalos de I/O em queries (pequeno overhead)
    recommendations << "track_functions = 'all'" # Coleta estatísticas de tempo de execução de funções/procedimentos
    recommendations << "log_parser_stats = off" # Geralmente 'off', a menos que esteja depurando o parser
    recommendations << "log_planner_stats = off" # Geralmente 'off', a menos que esteja depurando o planner
    recommendations << "log_executor_stats = off" # Geralmente 'off', a menos que esteja depurando o executor

    # Outras Configurações
    recommendations << "\n# Outras Configurações"
    recommendations << "max_worker_processes = #{cpu_cores}" # Pode ser igual ao número de núcleos
    # max_parallel_workers_per_gather: Número máximo de workers que uma única query pode usar.
    recommendations << "max_parallel_workers_per_gather = #{(cpu_cores / 2).to_i}" # Ex: metade dos núcleos
    recommendations << "max_parallel_workers = #{cpu_cores}" # Limite total de workers paralelos no sistema
    recommendations << "bytea_output = 'hex'" # Formato de saída para dados bytea (hex é mais legível)
    recommendations << "default_statistics_target = 500" # Aumentar para tabelas grandes pode melhorar a qualidade dos planos do otimizador (padrão 100)

    recommendations.join("\n")
  end

  # Gera um diff entre o conteúdo do arquivo atual e o conteúdo recomendado.
  def self.generate_diff(current_file_path, recommended_content)
    # Cria um arquivo temporário com o conteúdo recomendado
    Tempfile.create(['recommended_pg_conf', '.conf']) do |temp_file|
      temp_file.write(recommended_content)
      temp_file.close

      # Executa o comando diff
      # '-u' para formato unificado
      # '2>&1' redireciona stderr para stdout para capturar erros do diff
      diff_output, status = Open3.capture2("diff -u #{current_file_path} #{temp_file.path}")

      # Se o status for 0, não há diferenças. Se for 1, há diferenças (não é um erro).
      if status.exitstatus == 0
        return "" # Sem diferenças
      elsif status.exitstatus == 1
        return diff_output
      else
        warn "Erro ao gerar diff (código de saída: #{status.exitstatus}): #{diff_output}"
        return "Erro ao gerar diff."
      end
    end
  rescue StandardError => e
    warn "Erro ao gerar diff: #{e.message}"
    "Erro ao gerar diff."
  end
end