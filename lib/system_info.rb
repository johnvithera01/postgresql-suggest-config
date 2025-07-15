# lib/system_info.rb
require 'json' # Certifique-se de que a gem 'json' está disponível (é padrão no Ruby)

module SystemInfo
  # Retorna o tipo de disco (SSD ou HDD).
  # Tenta uma detecção mais robusta para macOS e Linux.
  def self.get_disk_type
    case RUBY_PLATFORM
    when /darwin/ # macOS
      output = `system_profiler SPSerialATADataType 2>/dev/null`
      if output.include?("Solid State: Yes")
        return "SSD"
      end
      "HDD (ou tipo não explicitamente reportado como SSD)"
    when /linux/ # Ubuntu e outras distros Linux
      output = `lsblk -d -o NAME,ROTA --json 2>/dev/null`
      
      if output.empty? || !output.strip.start_with?('{')
        warn "lsblk --json não retornou saída válida. Tentando método alternativo."
        output_fallback = `lsblk -d -o NAME,ROTA 2>/dev/null`
        if output_fallback.lines.any? { |line| line =~ /\s+0\s*$/ }
          return "SSD"
        elsif output_fallback.lines.any? { |line| line =~ /\s+1\s*$/ }
          return "HDD"
        end
        return "Desconhecido (erro na leitura do lsblk)"
      end

      data = JSON.parse(output)
      
      data['blockdevices'].each do |device|
        if device['type'] == 'disk' && device['rota'] == false # 'false' para não rotacional (SSD)
          return "SSD"
        end
      end
      
      "HDD (ou tipo não especificado como SSD)"
    else
      "Desconhecido (SO não suportado para detecção de disco)"
    end
  rescue StandardError => e
    warn "Erro ao obter tipo de disco: #{e.message}"
    "Erro na detecção"
  end

  # Retorna a quantidade de RAM (total e livre) em MB.
  def self.get_ram_info
    case RUBY_PLATFORM
    when /darwin/ # macOS
      output = `sysctl -n hw.memsize 2>/dev/null`.strip.to_i
      total_bytes = output
      mem_output = `top -l 1 -s 0 -n 0 | grep PhysMem 2>/dev/null`
      if mem_output =~ /PhysMem:\s*(\d+\.?\d*[GMK])\s*used,\s*(\d+\.?\d*[GMK])\s*free,\s*(\d+\.?\d*[GMK])\s*inactive/
        used_mb = convert_to_mb($1)
        free_mb = convert_to_mb($2)
        inactive_mb = convert_to_mb($3)
        total_mb = used_mb + free_mb + inactive_mb # Aproximação total
        { total: "#{total_bytes / (1024**3)} GB", free: "#{free_mb.round(2)} MB", total_mb: total_mb.round(2) }
      else
        { total: "#{total_bytes / (1024**3)} GB", free: "N/A", total_mb: total_bytes / (1024**2).to_f }
      end
    when /linux/ # Ubuntu e outras distros Linux
      meminfo = `cat /proc/meminfo 2>/dev/null`
      total_kb = meminfo.match(/MemTotal:\s*(\d+)\s*kB/)&.[](1).to_i
      free_kb = meminfo.match(/MemAvailable:\s*(\d+)\s*kB/)&.[](1).to_i
      { total: "#{(total_kb / 1024.0).round(2)} MB", free: "#{(free_kb / 1024.0).round(2)} MB", total_mb: (total_kb / 1024.0).round(2) }
    else
      { total: "N/A", free: "N/A", total_mb: 0 }
    end
  rescue StandardError => e
    warn "Erro ao obter informações de RAM: #{e.message}"
    { total: "Erro", free: "Erro", total_mb: 0 }
  end

  # Retorna a quantidade de Swap (total e livre) em MB.
  def self.get_swap_info
    case RUBY_PLATFORM
    when /darwin/ # macOS
      output = `sysctl vm.swapusage 2>/dev/null`
      if output =~ /total = (\d+\.\d+)M\s+used = (\d+\.\d+)M\s+free = (\d+\.\d+)M/
        total_mb = $1.to_f.round(2)
        used_mb = $2.to_f.round(2)
        free_mb = $3.to_f.round(2)
        { total: "#{total_mb} MB", free: "#{free_mb} MB" }
      else
        { total: "N/A (macOS usa Compressed Memory)", free: "N/A" }
      end
    when /linux/ # Ubuntu e outras distros Linux
      meminfo = `cat /proc/meminfo 2>/dev/null`
      total_kb = meminfo.match(/SwapTotal:\s*(\d+)\s*kB/)&.[](1).to_i
      free_kb = meminfo.match(/SwapFree:\s*(\d+)\s*kB/)&.[](1).to_i
      { total: "#{(total_kb / 1024.0).round(2)} MB", free: "#{(free_kb / 1024.0).round(2)} MB" }
    else
      { total: "N/A", free: "N/A" }
    end
  rescue StandardError => e
    warn "Erro ao obter informações de Swap: #{e.message}"
    { total: "Erro", free: "Erro" }
  end

  # Retorna a quantidade de núcleos da CPU.
  def self.get_cpu_cores
    case RUBY_PLATFORM
    when /darwin/ # macOS
      `sysctl -n hw.ncpu 2>/dev/null`.strip.to_i
    when /linux/ # Ubuntu e outras distros Linux
      `nproc 2>/dev/null`.strip.to_i
    else
      "N/A"
    end
  rescue StandardError => e
    warn "Erro ao obter número de núcleos da CPU: #{e.message}"
    "Erro"
  end

  private

  # Converte valores como "12G", "4.0M", "1024K" para MB
  def self.convert_to_mb(value)
    numeric_value = value[/\d+\.?\d*/].to_f
    case value[-1].upcase
    when 'G'
      numeric_value * 1024
    when 'M'
      numeric_value
    when 'K'
      numeric_value / 1024.0
    else
      numeric_value / (1024.0 * 1024.0) # Assume bytes se não houver sufixo
    end
  end
end