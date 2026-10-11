(* The shipped locales of the update window: English plus the same set
   the reference plugin carries — zh-CN (Hans), zh-TW (Hant), ja, ko,
   de, fr, es, it, nl, pl, pt-BR, ru, tr, uk.

   [for_locale] resolves a language tag or POSIX locale to the best
   available table: same language+script+region, then language+script,
   then language+region, then language, then another variant of the
   language (except zh — Hans and Hant are not variants of each other),
   else English. Missing fields of a partial table fall back to
   English. *)

open Strings

let english =
  {
    title = "Software Update";
    menu_item = "Check for Updates…";
    checking = "Checking for updates…";
    cancel = "Cancel";
    ok = "OK";
    up_to_date = "You’re up to date!";
    up_to_date_message = "%[1]s %[2]s is currently the newest version available.";
    unavailable = "Updates Unavailable";
    unavailable_message = "%[1]s cannot update itself where it is installed. If a package manager installed it, update it there.";
    development_build = "Development builds do not update themselves.";
    error = "Update Error!";
    check_error = "An error occurred while checking for updates. Please try again later.";
    install_error = "An error occurred while installing the update. Please try again later.";
    available = "A new version of %[1]s is available!";
    available_message = "%[1]s %[2]s is now available—you have %[3]s. Would you like to install it now?";
    release_notes = "Release Notes:";
    automatic_downloads = "Automatically download and install updates in the future";
    skip = "Skip This Version";
    remind_later = "Remind Me Later";
    install = "Install Update";
    downloading = "Downloading update…";
    progress = "%[1]s of %[2]s";
    megabytes = "%s MB";
    verifying = "Verifying update…";
    installing = "Installing update…";
    ready = "Ready to Relaunch";
    ready_message = "%[1]s %[2]s is installed and starts the next time you open %[1]s. Relaunch now to start using it.";
    later = "Later";
    relaunch = "Relaunch Now";
    retry = "Retry";
    time_remaining = "%s left";
  }

(** The languages whose decimal mark is a comma. *)
let decimal_comma_langs =
  [ "de"; "es"; "fr"; "it"; "nl"; "pl"; "pt-BR"; "ru"; "tr"; "uk" ]

(** Languages written right-to-left; none is shipped yet, but an app
    may add one through the [~extra] table. *)
let rtl_langs = [ "ar"; "fa"; "he"; "ps"; "ur"; "yi" ]

(** The shipped tables besides English, by language tag. *)
let table =
  [ ("zh-CN",
     { title = "软件更新";
       menu_item = "检查更新…";
       checking = "正在检查更新…";
       cancel = "取消";
       ok = "好";
       up_to_date = "已是最新版本！";
       up_to_date_message = "%[1]s %[2]s 是目前可用的最新版本。";
       unavailable = "无法更新";
       unavailable_message = "%[1]s 无法在当前安装位置自行更新。如果它是通过软件包管理器安装的，请在那里更新。";
       development_build = "开发版本不会自行更新。";
       error = "更新出错！";
       check_error = "检查更新时出错，请稍后再试。";
       install_error = "安装更新时出错，请稍后再试。";
       available = "%[1]s 有新版本可用！";
       available_message = "%[1]s %[2]s 现已推出，你当前的版本是 %[3]s。要现在安装吗？";
       release_notes = "更新说明：";
       automatic_downloads = "以后自动下载并安装更新";
       skip = "跳过这个版本";
       remind_later = "稍后提醒我";
       install = "安装更新";
       downloading = "正在下载更新…";
       progress = "%[1]s / %[2]s";
       megabytes = "%s MB";
       verifying = "正在验证更新…";
       installing = "正在安装更新…";
       ready = "可以重新启动了";
       ready_message = "%[1]s %[2]s 已安装，将在下次打开 %[1]s 时启动。立即重新启动即可开始使用。";
       later = "稍后";
       relaunch = "立即重新启动";
       retry = "重试";
       time_remaining = "剩余 %s" });
    ("zh-TW",
     { title = "軟體更新";
       menu_item = "檢查更新項目…";
       checking = "正在檢查更新項目…";
       cancel = "取消";
       ok = "好";
       up_to_date = "已是最新版本！";
       up_to_date_message = "%[1]s %[2]s 是目前可用的最新版本。";
       unavailable = "無法更新";
       unavailable_message = "%[1]s 無法在目前的安裝位置自行更新。如果它是透過套件管理工具安裝的，請在那裡更新。";
       development_build = "開發版本不會自行更新。";
       error = "更新發生錯誤！";
       check_error = "檢查更新項目時發生錯誤，請稍後再試。";
       install_error = "安裝更新項目時發生錯誤，請稍後再試。";
       available = "%[1]s 有新版本可用！";
       available_message = "%[1]s %[2]s 現已推出，你目前的版本是 %[3]s。要立即安裝嗎？";
       release_notes = "版本說明：";
       automatic_downloads = "日後自動下載並安裝更新項目";
       skip = "略過此版本";
       remind_later = "稍後提醒我";
       install = "安裝更新項目";
       downloading = "正在下載更新項目…";
       progress = "%[1]s / %[2]s";
       megabytes = "%s MB";
       verifying = "正在驗證更新項目…";
       installing = "正在安裝更新項目…";
       ready = "準備重新啟動";
       ready_message = "%[1]s %[2]s 已安裝，會在下次打開 %[1]s 時啟動。立即重新啟動即可開始使用。";
       later = "稍後";
       relaunch = "立即重新啟動";
       retry = "重試";
       time_remaining = "剩餘 %s" });
    ("ja",
     { title = "ソフトウェア・アップデート";
       menu_item = "アップデートを確認…";
       checking = "アップデートを確認中…";
       cancel = "キャンセル";
       ok = "OK";
       up_to_date = "最新の状態です";
       up_to_date_message = "%[1]s %[2]s は現在入手できる最新バージョンです。";
       unavailable = "アップデートを利用できません";
       unavailable_message = "%[1]s はインストールされている場所では自動でアップデートできません。パッケージマネージャでインストールした場合は、そちらでアップデートしてください。";
       development_build = "開発用ビルドは自動でアップデートされません。";
       error = "アップデートエラー";
       check_error = "アップデートの確認中にエラーが起きました。後でもう一度お試しください。";
       install_error = "アップデートのインストール中にエラーが起きました。後でもう一度お試しください。";
       available = "%[1]s の新しいバージョンがあります";
       available_message = "%[1]s %[2]s が利用可能です（現在のバージョンは %[3]s）。今すぐインストールしますか？";
       release_notes = "リリースノート：";
       automatic_downloads = "今後はアップデートを自動的にダウンロードしてインストール";
       skip = "このバージョンをスキップ";
       remind_later = "後で通知";
       install = "アップデートをインストール";
       downloading = "アップデートをダウンロード中…";
       progress = "%[1]s / %[2]s";
       megabytes = "%s MB";
       verifying = "アップデートを検証中…";
       installing = "アップデートをインストール中…";
       ready = "再起動の準備ができました";
       ready_message = "%[1]s %[2]s がインストールされました。次回 %[1]s を開いたときに起動します。今すぐ再起動すると使い始められます。";
       later = "後で";
       relaunch = "今すぐ再起動";
       retry = "再試行";
       time_remaining = "残り %s" });
    ("ko",
     { title = "소프트웨어 업데이트";
       menu_item = "업데이트 확인…";
       checking = "업데이트 확인 중…";
       cancel = "취소";
       ok = "확인";
       up_to_date = "최신 버전입니다!";
       up_to_date_message = "%[1]s %[2]s이(가) 현재 사용 가능한 최신 버전입니다.";
       unavailable = "업데이트를 사용할 수 없음";
       unavailable_message = "%[1]s은(는) 설치된 위치에서 스스로 업데이트할 수 없습니다. 패키지 관리자로 설치했다면 해당 관리자에서 업데이트하십시오.";
       development_build = "개발용 빌드는 스스로 업데이트하지 않습니다.";
       error = "업데이트 오류!";
       check_error = "업데이트를 확인하는 중 오류가 발생했습니다. 나중에 다시 시도하십시오.";
       install_error = "업데이트를 설치하는 중 오류가 발생했습니다. 나중에 다시 시도하십시오.";
       available = "%[1]s의 새 버전을 사용할 수 있습니다!";
       available_message = "%[1]s %[2]s을(를) 사용할 수 있습니다(현재 버전: %[3]s). 지금 설치하시겠습니까?";
       release_notes = "릴리즈 노트:";
       automatic_downloads = "앞으로 업데이트를 자동으로 다운로드하고 설치";
       skip = "이 버전 건너뛰기";
       remind_later = "나중에 알림";
       install = "업데이트 설치";
       downloading = "업데이트 다운로드 중…";
       progress = "%[1]s / %[2]s";
       megabytes = "%s MB";
       verifying = "업데이트 검증 중…";
       installing = "업데이트 설치 중…";
       ready = "다시 실행 준비 완료";
       ready_message = "%[1]s %[2]s이(가) 설치되었으며 다음에 %[1]s을(를) 열 때 실행됩니다. 지금 다시 실행하여 사용을 시작하십시오.";
       later = "나중에";
       relaunch = "지금 다시 실행";
       retry = "다시 시도";
       time_remaining = "%s 남음" });
    ("de",
     { title = "Softwareaktualisierung";
       menu_item = "Nach Updates suchen …";
       checking = "Suche nach Updates …";
       cancel = "Abbrechen";
       ok = "OK";
       up_to_date = "Sie sind auf dem neuesten Stand!";
       up_to_date_message = "%[1]s %[2]s ist derzeit die neueste verfügbare Version.";
       unavailable = "Updates nicht verfügbar";
       unavailable_message = "%[1]s kann sich an seinem Installationsort nicht selbst aktualisieren. Wurde es mit einer Paketverwaltung installiert, aktualisieren Sie es dort.";
       development_build = "Entwicklungs-Builds aktualisieren sich nicht selbst.";
       error = "Fehler beim Update!";
       check_error = "Beim Suchen nach Updates ist ein Fehler aufgetreten. Bitte versuchen Sie es später erneut.";
       install_error = "Beim Installieren des Updates ist ein Fehler aufgetreten. Bitte versuchen Sie es später erneut.";
       available = "Eine neue Version von %[1]s ist verfügbar!";
       available_message = "%[1]s %[2]s ist jetzt verfügbar – Sie haben %[3]s. Möchten Sie es jetzt installieren?";
       release_notes = "Versionshinweise:";
       automatic_downloads = "Updates künftig automatisch laden und installieren";
       skip = "Diese Version überspringen";
       remind_later = "Später erinnern";
       install = "Update installieren";
       downloading = "Update wird geladen …";
       progress = "%[1]s von %[2]s";
       megabytes = "%s MB";
       verifying = "Update wird überprüft …";
       installing = "Update wird installiert …";
       ready = "Bereit zum Neustart";
       ready_message = "%[1]s %[2]s ist installiert und startet, wenn Sie %[1]s das nächste Mal öffnen. Starten Sie jetzt neu, um es zu verwenden.";
       later = "Später";
       relaunch = "Jetzt neu starten";
       retry = "Erneut versuchen";
       time_remaining = "noch %s" });
    ("fr",
     { title = "Mise à jour de logiciels";
       menu_item = "Rechercher les mises à jour…";
       checking = "Recherche de mises à jour…";
       cancel = "Annuler";
       ok = "OK";
       up_to_date = "Vous êtes à jour !";
       up_to_date_message = "%[1]s %[2]s est actuellement la version la plus récente.";
       unavailable = "Mises à jour indisponibles";
       unavailable_message = "%[1]s ne peut pas se mettre à jour à l’emplacement où il est installé. S’il a été installé par un gestionnaire de paquets, mettez-le à jour depuis celui-ci.";
       development_build = "Les versions de développement ne se mettent pas à jour.";
       error = "Erreur de mise à jour !";
       check_error = "Une erreur est survenue lors de la recherche de mises à jour. Veuillez réessayer plus tard.";
       install_error = "Une erreur est survenue lors de l’installation de la mise à jour. Veuillez réessayer plus tard.";
       available = "Une nouvelle version de %[1]s est disponible !";
       available_message = "%[1]s %[2]s est maintenant disponible (vous avez la version %[3]s). Voulez-vous l’installer maintenant ?";
       release_notes = "Notes de version :";
       automatic_downloads = "Télécharger et installer automatiquement les mises à jour à l’avenir";
       skip = "Ignorer cette version";
       remind_later = "Me le rappeler plus tard";
       install = "Installer la mise à jour";
       downloading = "Téléchargement de la mise à jour…";
       progress = "%[1]s sur %[2]s";
       megabytes = "%s Mo";
       verifying = "Vérification de la mise à jour…";
       installing = "Installation de la mise à jour…";
       ready = "Prêt à relancer";
       ready_message = "%[1]s %[2]s est installé et démarrera la prochaine fois que vous ouvrirez %[1]s. Relancez maintenant pour l’utiliser.";
       later = "Plus tard";
       relaunch = "Relancer maintenant";
       retry = "Réessayer";
       time_remaining = "%s restantes" });
    ("es",
     { title = "Actualización de software";
       menu_item = "Buscar actualizaciones…";
       checking = "Buscando actualizaciones…";
       cancel = "Cancelar";
       ok = "Aceptar";
       up_to_date = "¡Ya tiene la versión más reciente!";
       up_to_date_message = "%[1]s %[2]s es la versión más reciente disponible.";
       unavailable = "Actualizaciones no disponibles";
       unavailable_message = "%[1]s no puede actualizarse en la ubicación donde está instalado. Si lo instaló un gestor de paquetes, actualícelo desde allí.";
       development_build = "Las versiones de desarrollo no se actualizan solas.";
       error = "¡Error de actualización!";
       check_error = "Se ha producido un error al buscar actualizaciones. Vuelva a intentarlo más tarde.";
       install_error = "Se ha producido un error al instalar la actualización. Vuelva a intentarlo más tarde.";
       available = "¡Hay una nueva versión de %[1]s disponible!";
       available_message = "%[1]s %[2]s ya está disponible (tiene la versión %[3]s). ¿Desea instalarla ahora?";
       release_notes = "Notas de la versión:";
       automatic_downloads = "Descargar e instalar actualizaciones automáticamente en el futuro";
       skip = "Omitir esta versión";
       remind_later = "Recordármelo más tarde";
       install = "Instalar actualización";
       downloading = "Descargando actualización…";
       progress = "%[1]s de %[2]s";
       megabytes = "%s MB";
       verifying = "Verificando actualización…";
       installing = "Instalando actualización…";
       ready = "Listo para reiniciar";
       ready_message = "%[1]s %[2]s está instalado y se abrirá la próxima vez que inicie %[1]s. Reinicie ahora para empezar a usarlo.";
       later = "Más tarde";
       relaunch = "Reiniciar ahora";
       retry = "Reintentar";
       time_remaining = "quedan %s" });
    ("it",
     { title = "Aggiornamento software";
       menu_item = "Controlla aggiornamenti…";
       checking = "Ricerca di aggiornamenti…";
       cancel = "Annulla";
       ok = "OK";
       up_to_date = "Hai già l’ultima versione!";
       up_to_date_message = "%[1]s %[2]s è attualmente la versione più recente disponibile.";
       unavailable = "Aggiornamenti non disponibili";
       unavailable_message = "%[1]s non può aggiornarsi nella posizione in cui è installato. Se è stato installato con un gestore di pacchetti, aggiornalo da lì.";
       development_build = "Le build di sviluppo non si aggiornano da sole.";
       error = "Errore di aggiornamento!";
       check_error = "Si è verificato un errore durante la ricerca di aggiornamenti. Riprova più tardi.";
       install_error = "Si è verificato un errore durante l’installazione dell’aggiornamento. Riprova più tardi.";
       available = "È disponibile una nuova versione di %[1]s!";
       available_message = "%[1]s %[2]s è ora disponibile (hai la versione %[3]s). Vuoi installarla adesso?";
       release_notes = "Note di rilascio:";
       automatic_downloads = "Scarica e installa automaticamente gli aggiornamenti in futuro";
       skip = "Salta questa versione";
       remind_later = "Ricordamelo più tardi";
       install = "Installa aggiornamento";
       downloading = "Download dell’aggiornamento…";
       progress = "%[1]s di %[2]s";
       megabytes = "%s MB";
       verifying = "Verifica dell’aggiornamento…";
       installing = "Installazione dell’aggiornamento…";
       ready = "Pronto per il riavvio";
       ready_message = "%[1]s %[2]s è installato e si avvierà la prossima volta che apri %[1]s. Riavvia ora per iniziare a usarlo.";
       later = "Più tardi";
       relaunch = "Riavvia ora";
       retry = "Riprova";
       time_remaining = "%s rimanenti" });
    ("nl",
     { title = "Software-update";
       menu_item = "Zoek naar updates…";
       checking = "Zoeken naar updates…";
       cancel = "Annuleer";
       ok = "OK";
       up_to_date = "Je bent up-to-date!";
       up_to_date_message = "%[1]s %[2]s is momenteel de nieuwste beschikbare versie.";
       unavailable = "Updates niet beschikbaar";
       unavailable_message = "%[1]s kan zichzelf niet bijwerken op de plek waar het is geïnstalleerd. Als een pakketbeheerder het heeft geïnstalleerd, werk het daar bij.";
       development_build = "Ontwikkelversies werken zichzelf niet bij.";
       error = "Fout bij update!";
       check_error = "Er is een fout opgetreden bij het zoeken naar updates. Probeer het later opnieuw.";
       install_error = "Er is een fout opgetreden bij het installeren van de update. Probeer het later opnieuw.";
       available = "Er is een nieuwe versie van %[1]s beschikbaar!";
       available_message = "%[1]s %[2]s is nu beschikbaar (je hebt %[3]s). Wil je deze nu installeren?";
       release_notes = "Release-opmerkingen:";
       automatic_downloads = "Updates voortaan automatisch downloaden en installeren";
       skip = "Sla deze versie over";
       remind_later = "Herinner me later";
       install = "Installeer update";
       downloading = "Update downloaden…";
       progress = "%[1]s van %[2]s";
       megabytes = "%s MB";
       verifying = "Update verifiëren…";
       installing = "Update installeren…";
       ready = "Klaar om opnieuw te starten";
       ready_message = "%[1]s %[2]s is geïnstalleerd en start de volgende keer dat je %[1]s opent. Start nu opnieuw om het te gebruiken.";
       later = "Later";
       relaunch = "Start nu opnieuw";
       retry = "Opnieuw proberen";
       time_remaining = "nog %s" });
    ("pl",
     { title = "Aktualizacja oprogramowania";
       menu_item = "Sprawdź aktualizacje…";
       checking = "Sprawdzanie aktualizacji…";
       cancel = "Anuluj";
       ok = "OK";
       up_to_date = "Masz najnowszą wersję!";
       up_to_date_message = "Wersja %[2]s aplikacji %[1]s jest obecnie najnowszą dostępną wersją.";
       unavailable = "Aktualizacje niedostępne";
       unavailable_message = "Aplikacja %[1]s nie może zaktualizować się w miejscu, w którym jest zainstalowana. Jeśli zainstalował ją menedżer pakietów, zaktualizuj ją tam.";
       development_build = "Wersje deweloperskie nie aktualizują się same.";
       error = "Błąd aktualizacji!";
       check_error = "Wystąpił błąd podczas sprawdzania aktualizacji. Spróbuj ponownie później.";
       install_error = "Wystąpił błąd podczas instalowania aktualizacji. Spróbuj ponownie później.";
       available = "Dostępna jest nowa wersja aplikacji %[1]s!";
       available_message = "Wersja %[2]s aplikacji %[1]s jest już dostępna (masz wersję %[3]s). Czy chcesz ją teraz zainstalować?";
       release_notes = "Informacje o wersji:";
       automatic_downloads = "W przyszłości automatycznie pobieraj i instaluj aktualizacje";
       skip = "Pomiń tę wersję";
       remind_later = "Przypomnij później";
       install = "Zainstaluj aktualizację";
       downloading = "Pobieranie aktualizacji…";
       progress = "%[1]s z %[2]s";
       megabytes = "%s MB";
       verifying = "Weryfikowanie uaktualnienia…";
       installing = "Instalowanie aktualizacji…";
       ready = "Gotowe do ponownego uruchomienia";
       ready_message = "Wersja %[2]s aplikacji %[1]s jest zainstalowana i uruchomi się przy następnym otwarciu aplikacji %[1]s. Uruchom ją ponownie teraz, aby zacząć z niej korzystać.";
       later = "Później";
       relaunch = "Uruchom ponownie";
       retry = "Ponów";
       time_remaining = "pozostało %s" });
    ("pt-BR",
     { title = "Atualização de Software";
       menu_item = "Verificar atualizações…";
       checking = "Verificando atualizações…";
       cancel = "Cancelar";
       ok = "OK";
       up_to_date = "Você já tem a versão mais recente!";
       up_to_date_message = "%[1]s %[2]s é a versão mais recente disponível.";
       unavailable = "Atualizações indisponíveis";
       unavailable_message = "%[1]s não pode se atualizar no local onde está instalado. Se ele foi instalado por um gerenciador de pacotes, atualize-o por lá.";
       development_build = "Versões de desenvolvimento não se atualizam sozinhas.";
       error = "Erro de atualização!";
       check_error = "Ocorreu um erro ao verificar atualizações. Tente novamente mais tarde.";
       install_error = "Ocorreu um erro ao instalar a atualização. Tente novamente mais tarde.";
       available = "Uma nova versão de %[1]s está disponível!";
       available_message = "%[1]s %[2]s já está disponível (você tem a versão %[3]s). Deseja instalá-la agora?";
       release_notes = "Notas da versão:";
       automatic_downloads = "Baixar e instalar atualizações automaticamente no futuro";
       skip = "Ignorar esta versão";
       remind_later = "Lembrar mais tarde";
       install = "Instalar atualização";
       downloading = "Baixando atualização…";
       progress = "%[1]s de %[2]s";
       megabytes = "%s MB";
       verifying = "Verificando a atualização…";
       installing = "Instalando atualização…";
       ready = "Pronto para reabrir";
       ready_message = "%[1]s %[2]s está instalado e será iniciado na próxima vez que você abrir %[1]s. Reabra agora para começar a usá-lo.";
       later = "Mais tarde";
       relaunch = "Reabrir agora";
       retry = "Tentar novamente";
       time_remaining = "restam %s" });
    ("ru",
     { title = "Обновление ПО";
       menu_item = "Проверить обновления…";
       checking = "Проверка обновлений…";
       cancel = "Отмена";
       ok = "ОК";
       up_to_date = "У вас последняя версия!";
       up_to_date_message = "%[1]s %[2]s — самая новая из доступных версий.";
       unavailable = "Обновления недоступны";
       unavailable_message = "Приложение %[1]s не может обновить себя в месте установки. Если оно установлено менеджером пакетов, обновите его там.";
       development_build = "Сборки для разработки не обновляются сами.";
       error = "Ошибка обновления!";
       check_error = "При проверке обновлений произошла ошибка. Повторите попытку позже.";
       install_error = "При установке обновления произошла ошибка. Повторите попытку позже.";
       available = "Доступна новая версия %[1]s!";
       available_message = "Доступна версия %[1]s %[2]s (у вас %[3]s). Установить её сейчас?";
       release_notes = "Что нового:";
       automatic_downloads = "Автоматически загружать и устанавливать обновления в будущем";
       skip = "Пропустить эту версию";
       remind_later = "Напомнить позже";
       install = "Установить обновление";
       downloading = "Загрузка обновления…";
       progress = "%[1]s из %[2]s";
       megabytes = "%s МБ";
       verifying = "Проверка обновления…";
       installing = "Установка обновления…";
       ready = "Готово к перезапуску";
       ready_message = "%[1]s %[2]s установлено и запустится при следующем открытии %[1]s. Перезапустите сейчас, чтобы начать пользоваться новой версией.";
       later = "Позже";
       relaunch = "Перезапустить";
       retry = "Повторить";
       time_remaining = "осталось %s" });
    ("tr",
     { title = "Yazılım Güncelleme";
       menu_item = "Güncellemeleri Denetle…";
       checking = "Güncellemeler denetleniyor…";
       cancel = "Vazgeç";
       ok = "Tamam";
       up_to_date = "En son sürümü kullanıyorsunuz!";
       up_to_date_message = "%[1]s %[2]s şu anda mevcut en yeni sürüm.";
       unavailable = "Güncellemeler Kullanılamıyor";
       unavailable_message = "%[1]s yüklü olduğu konumda kendini güncelleyemiyor. Bir paket yöneticisiyle yüklendiyse oradan güncelleyin.";
       development_build = "Geliştirme sürümleri kendilerini güncellemez.";
       error = "Güncelleme Hatası!";
       check_error = "Güncellemeler denetlenirken bir hata oluştu. Lütfen daha sonra yeniden deneyin.";
       install_error = "Güncelleme yüklenirken bir hata oluştu. Lütfen daha sonra yeniden deneyin.";
       available = "%[1]s için yeni bir sürüm var!";
       available_message = "%[1]s %[2]s artık kullanılabilir (sizdeki sürüm %[3]s). Şimdi yüklemek ister misiniz?";
       release_notes = "Sürüm Notları:";
       automatic_downloads = "Gelecekte güncellemeleri otomatik olarak indir ve yükle";
       skip = "Bu Sürümü Atla";
       remind_later = "Daha Sonra Hatırlat";
       install = "Güncellemeyi Yükle";
       downloading = "Güncelleme indiriliyor…";
       progress = "%[1]s / %[2]s";
       megabytes = "%s MB";
       verifying = "Güncelleme doğrulanıyor…";
       installing = "Güncelleme yükleniyor…";
       ready = "Yeniden Başlatmaya Hazır";
       ready_message = "%[1]s %[2]s yüklendi ve %[1]s bir sonraki açılışında başlayacak. Kullanmaya başlamak için şimdi yeniden başlatın.";
       later = "Daha Sonra";
       relaunch = "Şimdi Yeniden Başlat";
       retry = "Yeniden dene";
       time_remaining = "%s kaldı" });
    ("uk",
     { title = "Оновлення ПЗ";
       menu_item = "Перевірити оновлення…";
       checking = "Перевірка оновлень…";
       cancel = "Скасувати";
       ok = "OK";
       up_to_date = "У вас остання версія!";
       up_to_date_message = "%[1]s %[2]s — найновіша доступна версія.";
       unavailable = "Оновлення недоступні";
       unavailable_message = "Застосунок %[1]s не може оновити себе в місці встановлення. Якщо його встановив менеджер пакетів, оновіть його там.";
       development_build = "Збірки для розробки не оновлюються самі.";
       error = "Помилка оновлення!";
       check_error = "Під час перевірки оновлень сталася помилка. Спробуйте пізніше.";
       install_error = "Під час встановлення оновлення сталася помилка. Спробуйте пізніше.";
       available = "Доступна нова версія %[1]s!";
       available_message = "Доступна версія %[1]s %[2]s (у вас %[3]s). Встановити її зараз?";
       release_notes = "Що нового:";
       automatic_downloads = "Автоматично завантажувати та встановлювати оновлення надалі";
       skip = "Пропустити цю версію";
       remind_later = "Нагадати пізніше";
       install = "Встановити оновлення";
       downloading = "Завантаження оновлення…";
       progress = "%[1]s з %[2]s";
       megabytes = "%s МБ";
       verifying = "Перевірка оновлення…";
       installing = "Встановлення оновлення…";
       ready = "Готово до перезапуску";
       ready_message = "%[1]s %[2]s встановлено, і ця версія запуститься під час наступного відкриття %[1]s. Перезапустіть зараз, щоб почати нею користуватися.";
       later = "Пізніше";
       relaunch = "Перезапустити";
       retry = "Повторити";
       time_remaining = "залишилось %s" }) ]

let locales = ("en", english) :: table

(** Split a language tag or POSIX locale into language, script and
    region: "zh_TW.UTF-8", "sr_RS@latin", "pt-BR" all parse. *)
let parse_locale locale =
  let locale, _, _ = cut locale '.' in
  let locale, _, _ = cut locale '@' in
  let parts =
    String.split_on_char '-' locale
    |> List.concat_map (String.split_on_char '_')
    |> List.filter (fun s -> s <> "")
  in
  match parts with
  | [] -> ("", "", "")
  | lang :: rest ->
    let script = ref "" and region = ref "" in
    List.iter
      (fun p ->
        let n = String.length p in
        if n = 4 then
          script :=
            String.uppercase_ascii (String.sub p 0 1)
            ^ String.lowercase_ascii (String.sub p 1 3)
        else if n = 2 || (n = 3 && p.[0] >= '0' && p.[0] <= '9') then
          region := String.uppercase_ascii p)
      rest;
    (String.lowercase_ascii lang, !script, !region)

let base_language tag =
  match String.index_opt tag '-' with
  | Some i -> String.lowercase_ascii (String.sub tag 0 i)
  | None -> String.lowercase_ascii tag

let eq_ci a b = String.lowercase_ascii a = String.lowercase_ascii b

(** [match_language locale available] picks the tag of [available] that
    best matches [locale], or "en" without a match. The shipped zh
    tables are keyed by region (zh-CN Hans, zh-TW Hant): a script tag
    maps to its canonical region (Hans→CN, Hant→TW), and a zh locale
    with neither picks Hant for TW/HK/MO regions, Hans elsewhere. *)
let match_language locale available =
  let lang, script, region = parse_locale locale in
  if lang = "" then "en"
  else begin
    let script, region =
      if lang = "zh" then begin
        let script =
          if script = "" then
            match region with
            | "TW" | "HK" | "MO" -> "Hant"
            | _ -> "Hans"
          else script
        in
        let region =
          match script with
          | "Hant" -> "TW"
          | _ -> if region = "" then "CN" else region
        in
        (script, region)
      end
      else (script, region)
    in
    let candidates =
      (if script <> "" then
         [ lang ^ "-" ^ script ^ "-" ^ region; lang ^ "-" ^ script ]
       else [])
      @ [ lang ^ "-" ^ region; lang ]
    in
    let find cs =
      List.find_map
        (fun c -> List.find_opt (fun a -> eq_ci a c) available)
        cs
    in
    match find candidates with
    | Some a -> a
    | None -> (
      if lang <> "zh" then
        match
          List.find_opt (fun a -> base_language a = lang) available
        with
        | Some a -> a
        | None -> "en"
      else "en")
  end

(** [for_locale locale ~extra] resolves the texts the window shows:
    the app-supplied table for the language (merged over the shipped
    one), else the shipped one; missing fields fill from English. *)
let for_locale ?(extra = []) locale : text =
  let available = List.map fst (locales @ extra) in
  let lang = match_language locale available in
  let s =
    match
      List.find_opt (fun (l, _) -> eq_ci l lang) extra
    with
    | Some (_, s) -> s
    | None -> Strings.empty
  in
  let s =
    match List.find_opt (fun (l, _) -> eq_ci l lang) locales with
    | Some (_, own) -> merge s own
    | None -> s
  in
  let s = merge s english in
  {
    s;
    lang;
    decimal_comma = List.exists (eq_ci lang) decimal_comma_langs;
    rtl = List.exists (eq_ci (base_language lang)) rtl_langs;
  }

(** [check_extra extra] reports the app-supplied tables whose formats
    are invalid. *)
let check_extra extra =
  List.filter_map
    (fun (l, s) ->
      match Strings.check s with
      | Stdlib.Ok () -> None
      | Stdlib.Error m -> Some (Printf.sprintf "strings of %S: %s" l m))
    extra
