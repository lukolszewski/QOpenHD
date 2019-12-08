#include "openhdsettings.h"

#include <QtNetwork>
#include <QThread>
#include <QtConcurrent>

#define SETTINGS_PORT 1011
#define SETTINGS_IP "192.168.2.1"

OpenHDSettings::OpenHDSettings(QObject *parent) : QObject(parent) {
    qDebug() << "OpenHDSettings::OpenHDSettings()";
    initSettings();
}


void OpenHDSettings::initSettings() {
    qDebug() << "OpenHDSettings::initSettings()";
    settingSocket = new QUdpSocket(this);
    settingSocket->bind(QHostAddress::Any, 5115);
    connect(settingSocket, SIGNAL(readyRead()), this, SLOT(processDatagrams()));

    connect(&timer, &QTimer::timeout, this, &OpenHDSettings::checkSettingsLoadTimeout);

    // internal signal from background thread
    connect(this, &OpenHDSettings::savingSettingsStart, this, &OpenHDSettings::_savingSettingsStart);
    connect(this, &OpenHDSettings::savingSettingsFinish, this, &OpenHDSettings::_savingSettingsFinish);
}

void OpenHDSettings::set_ground_available(bool ground_available) {
    m_ground_available = ground_available;
    emit ground_available_changed(m_ground_available);
}

void OpenHDSettings::set_loading(bool loading) {
    m_loading = loading;
    emit loadingChanged(m_loading);
}

void OpenHDSettings::set_saving(bool saving) {
    m_saving = saving;
    emit savingChanged(m_saving);
}

void OpenHDSettings::checkSettingsLoadTimeout() {
    qint64 current = QDateTime::currentSecsSinceEpoch();
    //fallback in case the ground pi never sends back "ConfigEnd=ConfigEnd"
    if (current - start > 30) {
        timer.stop();
        emit allSettingsChanged(m_allSettings);
        set_loading(false);
    }
}

void OpenHDSettings::reboot() {
    if (m_saving) {
        return;
    }
#if defined(__rasp_pi__)
    QProcess process;
    process.start("/sbin/reboot");
    process.waitForFinished();
#else
    QByteArray r = QByteArray("RequestReboot");
    settingSocket->writeDatagram(r, QHostAddress(groundAddress), SETTINGS_PORT);

#endif
}

void OpenHDSettings::shutdown() {
    if (m_saving) {
        return;
    }
#if defined(__rasp_pi__)
    QProcess process;
    process.start("/sbin/shutdown -h -P now");
    process.waitForFinished();
#else
    QByteArray r = QByteArray("RequestShutdown");
    settingSocket->writeDatagram(r, QHostAddress(groundAddress), SETTINGS_PORT);
#endif
}


void OpenHDSettings::_savingSettingsStart() {
    set_saving(true);
}

void OpenHDSettings::_savingSettingsFinish() {
    set_saving(false);
}

void OpenHDSettings::saveSettings(VMap remoteSettings) {
    qDebug() << "OpenHDSettings::saveSettings()";

    // run the real network calls in the background. needs some minor changes to avoid threading related
    // errors
    //QFuture<void> future = QtConcurrent::run(this, &OpenHDSettings::_saveSettings, remoteSettings);
    _saveSettings(remoteSettings);
}

void OpenHDSettings::_saveSettings(VMap remoteSettings) {
    if (m_saving || m_loading) {
        return;
    }
    set_saving(true);
    //emit savingSettingsStart();

    settingsCount = remoteSettings.count();

    QMapIterator<QString, QVariant> i(remoteSettings);
    while (i.hasNext()) {
        i.next();

        QByteArray r = QByteArray("RequestChangeSettings");
        r.append(i.key());
        r.append('=');
        r.append(i.value().toString());
        settingSocket->writeDatagram(r, QHostAddress(groundAddress), SETTINGS_PORT);

        QThread::msleep(30);
    }
    set_saving(false);

    //emit savingSettingsFinish();
}

VMap OpenHDSettings::getAllSettings() {
    return m_allSettings;
}

void OpenHDSettings::fetchSettings() {
    if (m_loading || m_saving) {
        return;
    }
    set_loading(true);

    qDebug() << "OpenHDSettings::fetchSettings()";

    start = QDateTime::currentSecsSinceEpoch();
    timer.start(1000);

    QByteArray r = QByteArray("RequestAllSettings");
    QNetworkDatagram d(r);
    settingSocket->writeDatagram(r, QHostAddress(groundAddress), SETTINGS_PORT);
}


void OpenHDSettings::processDatagrams() {
    QByteArray datagram;

    while (settingSocket->hasPendingDatagrams()) {
        datagram.resize(int(settingSocket->pendingDatagramSize()));

        settingSocket->readDatagram(datagram.data(), datagram.size(), &groundAddress);

        emit groundStationIPUpdated(groundAddress.toString());
        set_ground_available(true);

        if (datagram == "ConfigRespConfigEnd=ConfigEnd") {
            timer.stop();
            emit allSettingsChanged(m_allSettings);
            set_loading(false);
        } else if (datagram.contains("SavedGround")) {
            settingsCount -= 1;
        } else {
            auto set = datagram.split('=');
            auto key = set.first();         
            // eliminate any zero length keys coming from the server, which aren't real settings
            if (key.length() <= 0) {
                return;
            }

            // ignore non-settings messages
            if (key.compare("GroundIP\n") == 0) {
                continue;
            }

            // remove ConfigResp from the beginning of each key
            datagram.remove(0, 10);
            /*
             * Find the FIRST equals sign in the rest of the datagram. Everything
             * before it is the key and everything after it is the value
             */
            auto split_location = datagram.indexOf("=");
            // copy just the key, without the equals sign and without altering the datagram
            key = datagram.mid(0, split_location);
            // cut the entire key and the equals sign out of the datagram...
            datagram.remove(0, split_location + 1);
            // ... leaving just the value remaining in the datagram
            auto val = datagram;

            m_allSettings.insert(QString(key), QVariant(val));
        }
    }
}

