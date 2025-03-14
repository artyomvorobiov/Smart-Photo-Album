const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

admin.initializeApp();

exports.notifyOnPhotoShare = functions.firestore
  .document('photos/{photoId}')
  .onUpdate(async (change, context) => {
    const beforeData = change.before.data();
    const afterData = change.after.data();

    // Если поле sharedWith не изменилось, функция ничего не делает
    if (JSON.stringify(beforeData.sharedWith) === JSON.stringify(afterData.sharedWith)) {
      return null;
    }

    // Определяем, какие пользователи были добавлены в sharedWith
    const beforeShared = beforeData.sharedWith || {};
    const afterShared = afterData.sharedWith || {};
    let newRecipients = [];
    for (const userId in afterShared) {
      if (!beforeShared.hasOwnProperty(userId)) {
        newRecipients.push(userId);
      }
    }
    if (newRecipients.length === 0) return null;

    // Получаем FCM-токены для новых получателей (поле fcmTokens – массив токенов)
    const tokens = [];
    const userDocsPromises = newRecipients.map(userId =>
      admin.firestore().collection('users').doc(userId).get()
    );
    const userDocs = await Promise.all(userDocsPromises);
    userDocs.forEach(doc => {
      if (doc.exists) {
        const data = doc.data();
        if (data.fcmTokens && Array.isArray(data.fcmTokens)) {
          tokens.push(...data.fcmTokens);
        }
      }
    });

    if (tokens.length > 0) {
      // Формируем сообщение для отправки.
      // Используем поле "url" для превью фотографии в уведомлении.
      const message = {
        tokens: tokens,
        notification: {
          title: "Новое фото для вас!",
          body: "Вам отправили фотографию.",
          image: afterData.url || null, // Используем url из документа фото
        },
        data: {
          photoId: context.params.photoId,
        },
        android: {
          collapseKey: "photo_share"
        }
      };
      const response = await admin.messaging().sendEachForMulticast(message);
      console.log("Ответ отправки: ", response);
      return response;
    }
    return null;
  });