/* Invictus: "I've saved my files" page for Calamares.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#ifndef INVICTUS_DISKCHECKVIEWSTEP_H
#define INVICTUS_DISKCHECKVIEWSTEP_H

#include "DllMacro.h"
#include "utils/PluginFactory.h"
#include "viewpages/ViewStep.h"

#include <QObject>
#include <QString>
#include <QVariantMap>

class QCheckBox;
class QLabel;
class QWidget;

class PLUGINDLLEXPORT DiskCheckViewStep : public Calamares::ViewStep
{
    Q_OBJECT

public:
    explicit DiskCheckViewStep( QObject* parent = nullptr );
    ~DiskCheckViewStep() override;

    QString prettyName() const override;
    QWidget* widget() override;

    bool isNextEnabled() const override;
    bool isBackEnabled() const override;
    bool isAtBeginning() const override;
    bool isAtEnd() const override;

    Calamares::JobList jobs() const override;

    void onActivate() override;
    void setConfigurationMap( const QVariantMap& configurationMap ) override;

private:
    QWidget* m_widget;
    QLabel* m_title;
    QLabel* m_found;
    QLabel* m_warning;
    QCheckBox* m_saved;
};

CALAMARES_PLUGIN_FACTORY_DECLARATION( DiskCheckViewStepFactory )

#endif
